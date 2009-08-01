module RedShift
  require "redshift/target/c/flow/delay"      if DelayFlow.needed
  require "redshift/target/c/flow/derivative" if DerivativeFlow.needed
  require "redshift/target/c/flow/euler"      if EulerDifferentialFlow.needed
  require "redshift/target/c/flow/algebraic"  if AlgebraicFlow.needed
  require "redshift/target/c/flow/rk4"        if RK4DifferentialFlow.needed
  require "redshift/target/c/flow/expr"
end

module RedShift; class Flow
  def translate flow_fn, result_var, rk_level, cl, orig_formula = nil
    translation = {}
    setup = []    ## should use accumulator
    
    orig_formula ||= @formula
    c_formula = orig_formula.dup
    strict = true
    
    re = /(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)(?!\w*\s*[(])/
    
    c_formula.gsub! re do |expr|

      unless translation[expr]
        link, var = $1, $2
        if link
          result =
            translate_link(link, var, translation, flow_fn, cl, expr, rk_level)
          strict &&= result # Don't combine with method call!!!
                    
        else # expr == 'var'
          varsym = var.intern
          
          link_type, link_strictness = cl.link_variables[varsym]
          
          if link_type
            # l ==> link_l
            strict &&= (link_strictness == :strict)

            link = var
            link_cname = "link_#{link}"
            unless translation[link]
              translation[link] = "ct.#{link_cname}"

              ct_struct = make_ct_struct(flow_fn, cl)

              link_type_ssn = link_type.shadow_struct.name
              ct_struct.declare link_cname => "#{link_type_ssn} *#{link_cname}"
              flow_fn.setup  link_cname => "ct.#{link_cname} = shadow->#{link}"
            end
            
          elsif (kind = cl.constant_variables[varsym])
            strict &&= (kind == :strict)
            translation[var] = "shadow->#{var}"
          
          elsif (kind = cl.continuous_variables[varsym])
            # x ==> var_x
            strict &&= (kind == :strict)

            var_cname = "var_#{var}"
            sh_cname = "shadow"
            cs_cname = "cont_state"
            cont_var = "#{cs_cname}->#{var}"
            translation[var] = var_cname

            flow_fn.declare var_cname => "double    #{var_cname}"
            flow_fn.setup var_cname => %{
              if (#{cont_var}.algebraic) {
                if (#{cont_var}.rk_level < shadow->world->rk_level ||
                   (shadow->world->rk_level == 0 &&
                    (#{cont_var}.strict ? !#{cont_var}.d_tick :
                     #{cont_var}.d_tick != shadow->world->d_tick)
                    ))
                  (*#{cont_var}.flow)((ComponentShadow *)#{sh_cname});
              }
              else {
                #{cont_var}.d_tick = shadow->world->d_tick;
              }
            }
            # The d_tick assignment is explained in component-gen.rb.
            setup << "#{var_cname} = #{cont_var}.value_#{rk_level};"
          
          elsif (kind = cl.input_variables[varsym])
            # x ==> var_x
            strict &&= (kind == :strict)
              # note that we check in #connect that the source var is strict

            var_cname = "var_#{var}"
            translation[var] = var_cname

            src_comp    = cl.src_comp(varsym)
            src_type    = cl.src_type(varsym)
            src_offset  = cl.src_offset(varsym)

            exc_uncn = cl.shadow_library.declare_class UnconnectedInputError
            msg_uncn = "Input #{var} is not connected."

            exc_circ = cl.shadow_library.declare_class CircularDefinitionError
            msg_circ = "Circularity in input variable #{var} " +
                  "of class #{cl.name}."

            flow_fn.declare var_cname => "double    #{var_cname}"

            # These are for following a chain of input connections:
            flow_fn.declare :tgt      => "struct target    *tgt"
            flow_fn.declare :sh       => "ComponentShadow  *sh"
            flow_fn.declare :depth    => "int              depth"

            flow_fn.setup var_cname => %{
              depth = 0;
              tgt = (struct target *)&shadow->#{src_comp};
            
            loop_#{var}:
              if (!tgt->psh || tgt->type == INPUT_NONE) {
                rs_raise(#{exc_uncn}, shadow->self, #{msg_uncn.inspect});
              }

              sh = (ComponentShadow *)tgt->psh;

              switch(tgt->type) {
              case INPUT_CONT_VAR: {
                ContVar *var = (ContVar *)&FIRST_CONT_VAR(sh);
                var += tgt->offset;

                if (var->algebraic) {
                  if (var->rk_level < sh->world->rk_level ||
                     (sh->world->rk_level == 0 &&
                      (var->strict ? !var->d_tick :
                       var->d_tick != sh->world->d_tick)
                      ))
                    (*var->flow)(sh);
                }
                else {
                  var->d_tick = sh->world->d_tick;
                }

                #{var_cname} = (&var->value_0)[sh->world->rk_level];
                break;
              }
              
              case INPUT_CONST:
                #{var_cname} = *(double *)(tgt->psh + tgt->offset);
                break;
              
              case INPUT_INP_VAR:
                tgt = (struct target *)(tgt->psh + tgt->offset);
                if (depth++ > 100) {
                  rs_raise(#{exc_circ}, shadow->self, #{msg_circ.inspect});
                }
                goto loop_#{var};
              
              default:
                assert(0);
              }
            }
          
          elsif /\A[eE]\z/ =~ var
            translation[expr] = expr # scientific notation
          
          elsif external_constant?(var)
            translation[expr] = expr
            
          else
            raise NameError, "Unknown variable: #{var}"
          end
          
        end
      end
      translation[expr]
    end
    
    yield strict if block_given?  ## funky way to return another value
    
    setup << "#{result_var} = #{c_formula}"
    
  rescue NameError, ArgumentError => ex
    ex.message << "\nclass: #{cl.name}\nformula:\n#{orig_formula}\n\n"
    raise ex
  end
  
  def external_constant? var
    RedShift.library.external_constant? var
  end
  
  CT_STRUCT_NAME = "Context"

  # Since MSVC doesn't support nested functions...
  def make_ct_struct(flow_fn, cl)
    sf = flow_fn.parent
    ct_struct = sf.declare![CT_STRUCT_NAME]

    if ct_struct
      ct_struct = ct_struct[1] ## hacky

    else
      ct_struct = sf.declare_struct(CT_STRUCT_NAME)

      ct_struct.declare :shadow => "#{cl.shadow_struct.name} *shadow"

      flow_fn.declare :ct => "#{CT_STRUCT_NAME} ct"
      flow_fn.setup   :ct_shadow => "ct.shadow = shadow"
    end

    ct_struct
  end
  
  # l.x  ==>  get_l__x()->value_n
  def translate_link(link, var, translation, flow_fn, cl, expr, rk_level)
    link_type, link_strictness = cl.link_variables[link.intern]
    raise(NameError, "No such link, #{link}") unless link_type
    strict = (link_strictness == :strict)
    
    flow_fn.include link_type.shadow_library_include_file
    
    link_cname = "link_#{link}"
    get_var_cname = "get_#{link}__#{var}"

    ct_struct = make_ct_struct(flow_fn, cl)

    varsym = var.intern
    if (kind = link_type.constant_variables[varsym])
      var_type = :constant
    elsif (kind = link_type.continuous_variables[varsym])
      var_type = :continuous
    elsif (kind = link_type.input_variables[varsym])
      var_type = :input
    else
      raise NameError, "Unknown variable: #{var} in #{link_type}"
    end

    strict &&= (kind == :strict)
    
    if var_type == :continuous or var_type == :input
      checked_var_cname = "checked_#{link}__#{var}" ## not quite unambig.
      ct_struct.declare checked_var_cname => "int #{checked_var_cname}"
      flow_fn.setup     checked_var_cname => "ct.#{checked_var_cname} = 0"
    end

    if var_type == :continuous
      link_cs_ssn = link_type.cont_state_class.shadow_struct.name
      link_cs_cname = "link_cs_#{link}"
      ct_struct.declare link_cs_cname => "#{link_cs_ssn} *#{link_cs_cname}"
    end

    unless translation[link + "."]
      translation[link + "."] = true # just so we know we've handled it

      unless translation[link]
        translation[link] = link_cname
        link_type_ssn = link_type.shadow_struct.name
        ct_struct.declare link_cname => "#{link_type_ssn} *#{link_cname}"
        flow_fn.setup     link_cname => "ct.#{link_cname} = shadow->#{link}"
      end ## same as below
    end

    sf = flow_fn.parent

    exc_nil = flow_fn.declare_class(NilLinkError) ## class var
    msg_nil = "Link #{link} is nil."

    case var_type
    when :continuous
      cs_cname = "ct->#{link_cs_cname}"
      cont_var = "#{cs_cname}->#{var}"
      sf.declare get_var_cname => %{
        inline static ContVar *#{get_var_cname}(#{CT_STRUCT_NAME} *ct) {
          if (!ct->#{checked_var_cname}) {
            ct->#{checked_var_cname} = 1;
            if (!ct->#{link_cname})
              rs_raise(#{exc_nil}, ct->shadow->self, #{msg_nil.inspect});
            #{cs_cname} = (#{link_cs_ssn} *)ct->#{link_cname}->cont_state;
            if (#{cont_var}.algebraic) {
              if (#{cont_var}.rk_level < ct->shadow->world->rk_level ||
                 (ct->shadow->world->rk_level == 0 &&
                  (#{cont_var}.strict ? !#{cont_var}.d_tick :
                   #{cont_var}.d_tick != ct->shadow->world->d_tick)
                 ))
                (*#{cont_var}.flow)((ComponentShadow *)ct->#{link_cname});
            }
            else {
              #{cont_var}.d_tick = ct->shadow->world->d_tick;
            }
          }
          return &(#{cont_var});
        }
      } ## algebraic test is same as above

      translation[expr] = "#{get_var_cname}(&ct)->value_#{rk_level}"
    
    when :constant
      sf.declare get_var_cname => %{
        inline static double #{get_var_cname}(#{CT_STRUCT_NAME} *ct) {
          if (!ct->#{link_cname})
            rs_raise(#{exc_nil}, ct->shadow->self, #{msg_nil.inspect});
          return ct->#{link_cname}->#{var};
        }
      }

      translation[expr] = "#{get_var_cname}(&ct)"
    
    when :input
      varsym = var.intern

      src_comp    = link_type.src_comp(varsym)
      src_type    = link_type.src_type(varsym)
      src_offset  = link_type.src_offset(varsym)

      exc_uncn = cl.shadow_library.declare_class UnconnectedInputError
      msg_uncn = "Input #{var} is not connected."

      exc_circ = cl.shadow_library.declare_class CircularDefinitionError
      msg_circ = "Circularity in input variable #{var} of class #{link_type}."

      result_name = "value_#{link}__#{var}"
      flow_fn.declare result_name => "double    #{result_name}"

      sf.declare get_var_cname => %{
        inline static double #{get_var_cname}(#{CT_STRUCT_NAME} *ct,
             double *presult) {
          if (!ct->#{checked_var_cname}) {
            struct target    *tgt   =
               (struct target *)&ct->#{link_cname}->#{src_comp};
            ComponentShadow  *sh;
            int              depth  = 0;

            ct->#{checked_var_cname} = 1;
            if (!ct->#{link_cname})
              rs_raise(#{exc_nil}, ct->shadow->self, #{msg_nil.inspect});
            
          loop:
            if (!tgt->psh || tgt->type == INPUT_NONE) {
              rs_raise(#{exc_uncn}, ct->shadow->self, #{msg_uncn.inspect});
            }

            sh = (ComponentShadow *)tgt->psh;

            switch(tgt->type) {
            case INPUT_CONT_VAR: {
              ContVar *var = (ContVar *)&FIRST_CONT_VAR(sh);
              var += tgt->offset;

              if (var->algebraic) {
                if (var->rk_level < sh->world->rk_level ||
                   (sh->world->rk_level == 0 &&
                    (var->strict ? !var->d_tick :
                     var->d_tick != sh->world->d_tick)
                    ))
                  (*var->flow)(sh);
              }
              else {
                var->d_tick = sh->world->d_tick;
              }

              *presult = (&var->value_0)[sh->world->rk_level];
              break;
            }

            case INPUT_CONST:
              *presult = *(double *)(tgt->psh + tgt->offset);
              break;

            case INPUT_INP_VAR:
              tgt = (struct target *)(tgt->psh + tgt->offset);
              if (depth++ > 100) {
                rs_raise(#{exc_circ}, ct->shadow->self, #{msg_circ.inspect});
              }
              goto loop;

            default:
              assert(0);
            }
          }
          
          return *presult;
        }
      }

      translation[expr] = "#{get_var_cname}(&ct, &#{result_name})"
      
    else
      raise ArgumentError, "Bad var_type: #{var_type.inspect}"
    end

    return strict
  end    
end; end

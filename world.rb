require 'option-block/option-block'
require 'pstore'
require 'redshift/component'

module RedShift

class ZenoError < RuntimeError; end

class World
  include OptionBlock
  include Enumerable
  include CShadow; shadow_library Component

  option_block_defaults \
    :name         =>  nil,
    :time_step    =>  0.1,
###    :zeno_limit   =>  -1, ## Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  
  @@count = 0

  attr_reader :step_count
  
  def started?; @started; end

  shadow_attr_writer   :time_step    => "double   time_step"
  shadow_attr_accessor :components   => Array
  shadow_attr_accessor :zeno_limit   => "long     zeno_limit"
  protected :time_step=, :components=
  ### what about dynamically changing time step?
  
  def self.new(*args, &block)
    unless Component.committed? or CLib.empty?
      Component.commit
      new(*args, &block)
    end
  end
  
  def initialize(&block)
    super ##??
    
    self.components = []

    @name           = options[:name] || "#{type} #{@@count}"
    self.time_step  = options[:time_step]
###    self.zeno_limit = options[:zeno_limit]
    self.zeno_limit = -1
    @clock_start    = options[:clock_start]
    @clock_finish   = options[:clock_finish]
    
    @step_count = 0
    
    @@count += 1

  end
  
  def do_setup
    type.do_setup self
    if @setup_procs
      for pr in @setup_procs
        instance_eval(&pr)
      end
    end
  end
  private :do_setup
  
  def self.do_setup instance
    superclass.do_setup instance if superclass.respond_to? :do_setup
    if @setup_procs
      for pr in @setup_procs
        instance.instance_eval(&pr)
      end
    end
  end

  def create(component_class, &block)
    c = component_class.new(self, &block)
    components << c
    c
  end
  
  def remove c
    components.delete c
  end
  
  
  def run(steps = 1)
  
    unless @started
      do_setup
      @started = true
    end
    
    step_discrete
    while (steps -= 1) >= 0 ## faster to use '(1..steps).each do' ?
      break if clock > @clock_finish
      @step_count += 1
      step_continuous
      step_discrete
      yield self if block_given?
    end
    
    self
  end

  define_method :step_continuous do
    declare :locals => %{
      VALUE             comp_rb_ary, *comp_ary;
      long              len;
      long              var_count;
      ContVar          *var, *end_var;
      long              ci;
      ComponentShadow  *comp_shdw;
    }.tabto(0)
    body %{
      time_step = shadow->time_step;    //# assign global
      comp_rb_ary = shadow->components;

      len = RARRAY(comp_rb_ary)->len;
      comp_ary = RARRAY(comp_rb_ary)->ptr;
      
      for (rk_level = 0; rk_level <= 4; rk_level++) { //# assign global
        for (ci = 0; ci < len; ci++) {
          Data_Get_Struct(comp_ary[ci], ComponentShadow, comp_shdw);
          var_count = comp_shdw->type_data->var_count;
          var = (ContVar *)(&comp_shdw->cont_state->begin_vars);
          end_var = &var[var_count];

          while (var < end_var) {
            if (rk_level == 0) {
              var->rk_level = 0;
              if (!var->flow)
                var->value_1 = var->value_2 = var->value_3 = var->value_0;
            }
            else {
              if (var->flow &&
                  var->rk_level < rk_level &&
                  !var->algebraic)
                (*var->flow)(comp_shdw);
              if (rk_level == 4)
                var->d_tick = 0;      //# for next step_discrete
            }
            var++;
          }
        }
      }
      d_tick = 1; //# alg flows need to be recalculated
      rk_level = 0;
    } ## assumed that comp_ary[i] was a Component
  end
  private :step_continuous

if true
  define_method :step_discrete do
    declare :locals => %{
      VALUE             comp_rb_ary, *comp_ary;
      long              len;
      long              ci;
      ComponentShadow  *comp_shdw;
      long              done;
      long              zeno_counter;
      long              zeno_limit;
    }.tabto(0)
    body %{
      done = 0;
      zeno_counter = 0;
      zeno_limit = shadow->zeno_limit;
      
      while (!done) {
        done = Qtrue;
        
        comp_rb_ary = shadow->components; //# list might change each time thru

        len = RARRAY(comp_rb_ary)->len;
        comp_ary = RARRAY(comp_rb_ary)->ptr;
        
        for (ci = 0; ci < len; ci++) {
          done &= rb_funcall(comp_ary[ci],
                  #{declare_symbol(:step_discrete)}, 0);
        }
        
        zeno_counter += 1;
        if (zeno_counter > zeno_limit && zeno_limit >= 0) {
          if (zeno_counter > 2 * zeno_limit) {
            rb_raise(#{declare_class RedShift::ZenoError},
            "\\nExceeded zeno limit of %d.\\n", zeno_limit);
          }
          else {
            rb_funcall(shadow->self, #{declare_symbol :step_zeno},
                       1, INT2NUM(zeno_counter));
          }
        }
      }
    } ## assumed that comp_ary[i] was a Component
  end
else
  def step_discrete
    done = false
    zeno_counter = 0
    
    until done
      done = true
      each { |c| done &= c.step_discrete }
      
      zeno_counter += 1
#      if zeno_counter > @zeno_limit
      if zeno_counter > zeno_limit and zeno_limit >= 0
        raise ZenoError,
          "at count #{zeno_counter}, exceeded limit #{zeno_limit}."
      end
    end
  end
end
  private :step_discrete
  
  def step_zeno zeno_counter
    puts "Zeno step: #{zeno_counter} / #{zeno limit}"
    ## print out the active components and their transitions if $DEBUG_ZENO?
  end
  
  def clock
    @step_count * time_step + @clock_start
  end
  
  
  def garbage_collect
    self.components = []
    GC.start
    ObjectSpace.each_object(Component) do |c|
      if c.world == self
        components << c
      end
    end
  end
  
  
  def each(&b)
    components.each(&b)
  end
  
  def size
    components.size
  end
  
  def include? component
    component.world == self
  end
  alias member? include?
  
  def inspect
    if @started
      sprintf "<%s: %d step%s, %s second%s, %d component%s>",
        @name,
        @step_count, ("s" if @step_count != 1),
        clock, ("s" if clock != 1),
        size, ("s" if size != 1)
    else
      sprintf "<%s: not started. Do 'run 0' to setup, or 'run n' to run.>",
        @name
    end
  end
  
  
  def save filename = @name
    each { |c|
      c.instance_eval {
        @trans_cache_state = nil
        @cache_transitions = nil
      }
    } ## can get rid of this after moving discrete behavior into C code
    File.delete filename rescue SystemCallError
    store = PStore.new filename
    store.transaction do
      store['world'] = self
      yield store if block_given?
    end
  end
  
  
  def World.open filename
    world = nil
    store = PStore.new filename
    store.transaction do
      if store.root? 'world'
        world = store['world']
        yield store if block_given?
      end
    end
    if world
      world.each { |c| c.restore }
    end
    world
  end
  
end # class World

end # module RedShift

# A way to use a class-method-based DSL, like redshift, from within a module.
# Extend a module M with Modular. Then, use the DSL freely in M, even though M
# doesn't have the DSL methods. When you include M in some class, it "replays"
# the class methods. See examples/modular-component-def.rb.
module Modular
  def method_missing(meth, *args, &block)
    (@_modular_saved ||= []) << [meth, args, block, caller]
  end
  
# this would allow unquoted constants, such as state names, but it's a bit
# too much magic:
#  def const_missing(c)
#    c
#  end
  
  def included(m)
    @_modular_saved && @_modular_saved.each do |meth, args, block, where|
      begin
        m.send(meth, *args, &block)
      rescue => ex
        ex.set_backtrace where
        ex.message << " while applying methods from #{self}"
        raise ex
      end
    end
  end
end

if __FILE__ == $0

  class C # think: Component
    def self.foo x # think #state, #flow, or #transition
      p x
      yield if block_given?
    end
  end

  module M
    extend Modular
    foo 2 do puts "hi" end # using the DSL
  end

  class D < C
    include M
    foo 3
  end

end

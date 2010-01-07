# Shows how to connect input variables in parallel, and also in
# parallel with resets.

require "redshift"
include RedShift

class A < Component
  input :in
  continuous :x => 1
  constant :k => 1
  link :comp
  
  state :T
  
  flow T do
    diff " x' = k*in "
  end
  
  transition Enter => T do
    reset :comp => nil # in parallel with the connect
    if true
      connect :in => proc {comp.port(:x)}
# alternate syntaxes:
#      connect port(:in).to {comp.port(:x)}
#      port(:in).connect {comp.port(:x)}
#      connect { in {comp.port :x}; ... }
    else
      connect :in => [:comp, :x] # special case: literals
    end
    
    # The non-parallel equivalent, which would fail after
    # resetting comp to nil:
    #
    # action do
    #   port(:in) << comp.port(:x)
    # end
    ## actually this would fail as a post, but not as action
  end
end

w = World.new
w.time_step = 0.001
a0, a1 = (0..1).map {w.create(A)}
a0.comp = a1
a1.comp = a0

w.evolve 1
p a0, a1

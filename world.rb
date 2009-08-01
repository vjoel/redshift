# Copyright (c) 2001, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'option-block/option-block.rb'

module RedShift

class World

  include OptionBlock
  
  option_block_defaults {
    :name         =>  "World #{@@count}",
    :time_step    =>  0.1,
    :zeno_limit   =>  Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  }
  
  @@count = 0

#  attr_reader :components
  attr_reader :clock_now, :clock_start
  attr_accessor :name, :time_step, :zeno_limit, :clock_finish

  Infinity = 1.0/0.0

  def initialize
  
    super

    @components = {}

    @name          = options[:name]
    @time_step     = options[:time_step]
    @zeno_limit    = options[:zeno_limit]
    @clock_start   = options[:clock_start]
    @clock_finish  = options[:clock_finish]
    
    @clock_now = @clock_start

    @@count += 1

  end

  def create(component_class, initializer_hash = {}, &block)
    c = component_class.new(self, initializer_hash, &block)
    @components[c.id] = c
  end

  def run(steps = 1)
    # should start a thread to do this, if flag
    # go into gui mode, if flag
    
    step_discrete
    while (steps -= 1) >= 0
      break if @clock_now > @clock_finish
      step_continuous
      clock_now += time_step
      step_discrete
    end
    
  end

  def step_continuous

    @components.each do |c|
      # this should be delegated to the component
      # which would be more flexible, though more complex and slower
      c.state.flow.each do |f|
        f.update c, @time_step
      end
    end

  end

  def step_discrete
  
    done = false
    zeno_counter = 0
    
    while !done
    
      done = true
      zeno_counter += 1
      
      if zeno_counter >= @zeno_limit
        raise "Zeno error!"
      end
  
      @components.each do |c|
        # this should be delegated to the component
        # which would be more flexible, though more complex and slower
        
        if t = c.enabled_transition
          done = false
          t.take c
          c.disable
          # is this the right semantics?
        end
        
        c.state.transition.each do |t|
          if t.enabled
            done = false
            c.enabled_transition = t
          end
        end
      end
            
    end


  end
      
end # class World

end # module RedShift

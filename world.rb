require 'option-block/option-block.rb'

module RedShift

class World

  include OptionBlock
  
  Infinity = 1.0/0.0
  
  $RK_level = nil

  option_block_defaults \
    :name         =>  '"World #{@@count}"',
    :time_step    =>  0.1,
    :zeno_limit   =>  Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  
  @@count = 0

  attr_reader :components
  attr_reader :step_count #, :clock_start
#  attr_accessor :name, :time_step, :zeno_limit, :clock_finish

  def initialize(&block)
    
    super
    
    @components = {}

    @name          = eval options[:name]
    @time_step     = options[:time_step]
    @zeno_limit    = options[:zeno_limit]
    @clock_start   = options[:clock_start]
    @clock_finish  = options[:clock_finish]
    
    @step_count = 0
    
    @@count += 1

  end

  def create(component_class, &block)
    c = component_class.new(self, &block)
    @components[c.id] = c
  end
  
  def remove c
    @components.delete c.id
  end

  def run(steps = 1)
    
    step_discrete
    while (steps -= 1) >= 0
      break if clock > @clock_finish
      @step_count += 1
      step_continuous
      step_discrete
    end
    
  end


  def step_continuous
  
    $RK_level = 4   # need SEMAPHORE
    @components.each_value do |c|
      c.step_continuous @time_step
    end
    $RK_level = nil
   
  end


  def step_discrete
  
    $RK_level = nil # need SEMAPHORE

    done = false
    zeno_counter = 0
    
    while !done
    
      done = true
      @components.each_value do |c|
        done &= c.step_discrete
      end
            
      zeno_counter += 1
      if zeno_counter > @zeno_limit
        raise "Zeno error!"
      end
  
    end
  end
  
  def clock
    @step_count * @time_step
  end
  
  def collect
    @components = {}
    GC.start
    ObjectSpace.each_object(Component) do |c|
      if c.world == self
        @components[c.id] = c
      end
    end
  end
      
end # class World

end # module RedShift

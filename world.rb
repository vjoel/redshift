require 'option-block/option-block.rb'

module RedShift

class World

  include OptionBlock
  
  Infinity = 1.0/0.0

  option_block_defaults \
    :name         =>  '"World #{@@count}"',
    :time_step    =>  0.1,
    :zeno_limit   =>  Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  
  @@count = 0

  attr_reader :components
  attr_reader :clock_now #, :clock_start
#  attr_accessor :name, :time_step, :zeno_limit, :clock_finish

  def initialize(&block)
    
    super
    
    @components = {}

    @name          = eval options[:name]
    @time_step     = options[:time_step]
    @zeno_limit    = options[:zeno_limit]
    @clock_start   = options[:clock_start]
    @clock_finish  = options[:clock_finish]
    
    @clock_now = @clock_start

    @@count += 1

  end

  def create(component_class, &block)
    c = component_class.new(self, &block)
    @components[c.id] = c
  end

  def run(steps = 1)
    
    step_discrete
    while (steps -= 1) >= 0
      break if @clock_now > @clock_finish
      step_continuous
      @clock_now += @time_step
      step_discrete
    end
    
  end


  def step_continuous
  
    @components.each_value do |c|
      c.step_continuous @time_step
    end
   
  end


  def step_discrete
  
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
      
end # class World

end # module RedShift

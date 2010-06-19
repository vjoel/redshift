# Shows how to use a customized IRB shell to handle Ctrl-C interrupts

require 'redshift'
include RedShift

require 'redshift/util/plot'
include Plot::PlotUtils

# Adds an interactive ruby shell with plotting and animation commands.
module ShellWorld
  include RedShift::World::Shell

  def help
    puts <<-END
      The current object is #{self.inspect}. Some commands:

        q         -- quit
        sh!       -- enter a system command shell
        t.plot    -- plot recent history of t (try t=components[0])
        plot      -- plot recent history of all T instances
        run N     -- run quickly for N time steps (integer)
        evolve T  -- run quickly for T seconds (float)
        tk        -- turn on Tk window
        tk false  -- turn off Tk window

      Local vars persist between interrupts.
      Continue slow execution by pressing Ctrl-D (maybe Ctrl-Z on windows).
      Press Ctrl-C again to break into the shell.
    END
  end
  
  def sh!
    system ENV['SHELL'] || default_shell
  end
  
  def default_shell
    puts "No SHELL environment variable, trying /bin/bash"
    "/bin/bash"
  end
  
  def next_id
    @next_id ||= 1
    @next_id += 1
  end
  
  def plot
    gnuplot do |plot|
      plot.command 'set title "recent history"'
      plot.command "set xrange [*:*]"
      plot.command "set yrange [*:*]"
      grep(T) do |t|
        t.add_history_to_plot(plot)
      end
    end
    nil
  end
  
  def before_shell
    @tkar.catch_up_within 0 if @tkar
    puts "\nStopped #{self.inspect}"
  end
  
  def after_shell
    @tkar.catch_up_within 0 if @tkar
    puts "\nRunning #{self.inspect}"
  end
  
  def dragger id, x, y
    @th ||= {}
    t = @th[id] ||= grep(T).find {|t| t.id == id}
    t.x, t.y = x, y
  end
  
  def tk turn_on = true
    require 'redshift/util/tkar-driver'
    if turn_on
      if not @tkar or @tkar.closed?
        @tkar = TkarDriver.new(method :dragger) do |pipe|
          pipe.puts <<-END
            title Animation example
            background gray95
            height 600
            width 600
            view_at -50 -50
            zoom_to 4

            shape cone \ arc5,5,10,10,fc:yellow,oc:black,extent:30,start:165,style:pieslice \
    text2,2,anchor:c,justify:center,width:100,text:*0,fc:blue

            shape circle oval*0,*0,*1,*1,oc:red
          END
          ## the view_at seems to be needed to overcome a little
          ## centering bug in tkar

          (1..10).each do |i|
            pipe.puts "add circle #{next_id} - 0 0 0 0 #{5*i} #{-5*i}"
          end

          grep(T) do |t|
            pipe.puts t.tk_add
          end
        end

        tk_update
      end
      
    elsif not turn_on and @tkar
      @tkar.close
      @tkar = nil
    end
    @tkar
  end
  
  def tk_update
    @tkar and @tkar.update do |pipe|
      grep(T) do |t|
        pipe.puts t.tk_update
      end
    end
  end
end

class T < Component
  attr_accessor :name, :id
  
  default do
    @id = world.next_id
  end
  
  flow do
    diff " x' = -y "
    diff " y' =  x "
    
    alg  " r = atan2(x, -y) " # atan2(y', x'): angle of velocity vector
    
    # A simple, but crude, way to store recent history of a var
    delay " z = x ", :by => 10
  end
  
  def history
    ts = world.time_step
    t0 = world.clock - z_delay
    data = []
    z_buffer_data.each_with_index do |xi, i|
      if i % 4 == 0 # skip the integrator steps
        time = t0 + (i/4)*ts
        data << [time, xi] if time >= 0
      end
    end
    data << [world.clock, x]
    data
  end
  
  def add_history_to_plot(plot)
    plot.add history, "using 1:2 title \"#{name}.x\" with lines"
  end

  def plot
    gnuplot do |plot|
      plot.command 'set title "recent history"'
      plot.command "set xrange [*:*]"
      plot.command "set yrange [*:*]"
      add_history_to_plot(plot)
    end
    nil
  end

  # return string that adds an instance of the shape with label t.name,
  # position based on (x, y), and
  # rotation based on (x', y')
  def tk_add
    "add cone #{id} - 10 #{x} #{y} #{r}\n" +
    "param #{id} 0 #{name}"
  end
  
  # emit string representing current state
  def tk_update
    "moveto #{id} #{x} #{y}\n" +
    "rot #{id} #{r}"
  end
end

w = World.new
w.time_step = 0.01
w.extend ShellWorld

w.create T do |t|
  t.name = "a"
  t.x = 40
  t.y = 0
end
w.create T do |t|
  t.name = "b"
  t.x = 0
  t.y = 20
end

if false
  (1..10).each do |i|
    w.create T do |t|
      t.name = "c#{i}"
      t.x = i*5
      t.y = i*5
    end
  end
end

puts "^C to break into shell; 'help' for shell help"

if ARGV.delete "-t"
  w.tk
end

start_in_shell = ARGV.delete "-s"
w.shell.run if start_in_shell

loop do
  w.evolve 100000000 do
    puts "clock: #{w.clock}"
    w.tk_update
    sleep 0.01
  end
end

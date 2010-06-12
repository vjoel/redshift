# Shows how to use a customized IRB shell to handle Ctrl-C interrupts

require 'redshift'
require 'redshift/mixins/irb-shell'
include RedShift

require 'redshift/util/plot'
include Plot::PlotUtils

module ShellWorld
  include RedShift::Shellable

  def help
    puts <<-END
      The current object is #{self.inspect}. Some commands:

        q       -- quit
        sh!     -- enter a system command shell
        t.plot  -- plot recent history of t (try t=components[0])
        plot    -- plot recent history of all T instances

      Local vars persist between interrupts.
      Continue execution by pressing Ctrl-D (maybe Ctrl-Z on windows).
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
  
  def plot
    gnuplot do |plot|
      plot.command 'set title "recent history"'
      plot.command "set yrange [-1:1]"
      grep(T) do |t|
        t.add_history_to_plot(plot)
      end
    end
    nil
  end
end

class T < Component
  attr_accessor :name
  
  flow do
    diff " x' = -y "
    diff " y' =  x "
    
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
      plot.command "set yrange [-1:1]"
      add_history_to_plot(plot)
    end
    nil
  end
end

w = World.new
w.extend ShellWorld

w.create T do |t|
  t.name = "a"
  t.x = 1
  t.y = 0
end
w.create T do |t|
  t.name = "b"
  t.x = 0
  t.y = 1
end

start_in_shell = ARGV.delete "-s"

w.shell.install_interrupt_handler
w.shell.run if start_in_shell

w.evolve 100000000 do
  puts "clock: #{w.clock}"
  sleep 0.1
end

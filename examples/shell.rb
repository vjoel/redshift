# Shows how to use a customized IRB shell to handle Ctrl-C interrupts

require 'redshift'
require 'redshift/mixins/irb-shell'
include RedShift

require 'redshift/util/plot'
include Plot::PlotUtils

module ShellWorld
  include IRBShell
  
  def help
    puts <<-END
      The current object is #{self}. Type 'methods' for a list of commands.
      Some special commands:

        q       -- quit
        sh!     -- enter a command shell
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
    pl = gnuplot do |plot|
      grep(T) do |t|
        t.plot_cmds(plot)
      end
    end
    pl.command_history
  end
end

class T < Component
  flow do
    diff  " x' = -y "
    diff  " y' = x "
    
    # A simple, but crude, way to store history of a var
    delay " z = x ", :by => 10
  end

  def plot_data
    ts = world.time_step
    cl = world.clock - z_delay
    data = []
    z_buffer_data.each_with_index do |xi, i|
      data << [cl + i*ts, xi]
    end
    data
  end
  
  def plot_cmds(plot)
    plot.command 'set title "recent history"'
    plot.command "set xrange [0:#{z_delay}]"
    plot.add plot_data, "using 1:2 title \"x\" with lines"
  end

  def plot
    pl = gnuplot do |plot|
      plot_cmds(plot)
    end
    pl.command_history
  end
end

w = World.new
w.extend ShellWorld
w.create T do |t|
  t.x = 1
  t.y = 0
end
w.create T do |t|
  t.x = 0
  t.y = 1
end

start_in_shell = false

w.set_interrupt_handler
w.shell if start_in_shell
w.evolve 100000000 do
  puts "clock: #{w.clock}"
  sleep 0.1
end

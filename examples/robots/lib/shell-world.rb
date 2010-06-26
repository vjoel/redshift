require 'redshift/mixins/shell'
require 'redshift/util/plot'

# Adds an interactive ruby shell with plotting and animation commands.
module ShellWorld
  include RedShift::Shell
  
  def entered
    @entered ||= []
  end
  
  def exited
    @exited ||= []
  end

  def main_loop_with_shell_and_tk(argv=[])
    if argv.delete "-h"
      puts <<-END
        
        -s    start in shell
              (otherwise, run until ^C breaks into shell)
        
        -t    start with tk animation
              (otherwise, run without tk until the "tk" command)
        
      END
      
      exit
    end
    
    puts "^C to break into shell; 'help' for shell help"
    tk if argv.delete "-t"
    shell.run if argv.delete "-s"

    loop do
      evolve 100000000 do
        puts "clock: #{clock}"
        #sleep 0.01
      end
    end
  end

  def help
    puts <<-END
      The current object is #{self.inspect}. Some commands:

        q         -- quit
        sh!       -- enter a system command shell
        run N     -- run quickly for N time steps (integer)
        evolve T  -- run quickly for T seconds (float)
        tk        -- turn on Tk window (-t on command line to start this way)
        tk false  -- turn off Tk window

      Local vars persist between interrupts.
      Continue slow execution by pressing Ctrl-D (maybe Ctrl-Z on windows).
      Press Ctrl-C again to break into the shell. Use -s on command line
      to start in shell.
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
  
  def create(*)
    c = super
    entered << c
    c
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
    c = find {|c| c.id == id}
    c.x, c.y = x, y
  end
  
  def tk turn_on = true
    require 'redshift/util/tkar-driver'
    if turn_on
      if not @tkar or @tkar.closed?
        @tkar = TkarDriver.new(method :dragger) do |pipe|
          pipe.puts <<-END
            title Robot World
            background gray95
            height 600
            width 600
            view_at -50 -20
            zoom_to 4

            shape cone \ arc5,0,10,10,fc:yellow,oc:black,extent:30,start:165,style:pieslice \
    text2,2,anchor:c,justify:center,width:100,text:*0,fc:blue

            shape robot cone*0 \
             arc5,5,2,2,fc:green,oc:green,extent:*1,start:0,style:pieslice \
             arc5,-5,2,2,fc:red,oc:red,extent:*2,start:0,style:pieslice
            
            shape circle oval*0,*0,*1,*1,oc:red
            shape explosion oval*0,*0,*1,*1,oc:*2,fc:*2
            shape missile \
arc2,0,4,4,fc:red,oc:black,extent:20,start:170,style:pieslice

          END
          ## the view_at seems to be needed to overcome a little
          ## centering bug in tkar

          each do |component|
            pipe.puts component.tk_add if defined?(component.tk_add)
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
    if @tkar and
       (entered.size > 0 or exited.size > 0 or (clock % 0.1).abs < 0.01)
      @tkar.update do |pipe|
        entered.each do |component|
          pipe.puts component.tk_add if defined?(component.tk_add)
        end

        each do |component|
          pipe.puts component.tk_update if defined?(component.tk_update)
        end

        exited.each do |component|
          pipe.puts component.tk_delete if defined?(component.tk_delete)
        end
      end
    end
  end
  
  def run(*)
    super do
      tk_update
      entered.clear
      exited.clear
      yield self if block_given?
    end
  end
end

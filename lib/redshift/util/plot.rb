autoload :Tempfile, "tempfile"

# Interface to gnuplot and, eventually, other plotting apps.
module Plot
  # +app+ is the name of the plot program. Yields and returns the plot instance.
  # Use the #add, #command, and #show methods on this object.
  def Plot.new(app = ENV['PLOTTER'] || 'gnuplot', &block)
    plot =
      case app
      when /gnuplot/i
        Gnuplot.new app

      when /^matlab/i
        raise "matlab not supported yet.\n  Try 'gnuplot'."

      else
        raise "Plot doesn't recognize '#{app}'.\n  Try 'gnuplot'."
      end
    yield plot if block_given?
    plot
  end
  
  class GenericPlot
    # Array of strings that have been sent to the plot program.
    attr_reader :command_history
     
    def initialize app
      @app = app
      @files = []
      @command_queue = []
      @command_history = []
      @data_stuff = []
    end
    
    def clear_data
      @data_stuff = []
    end
    
    # Closes the plot window and cleans up tempfiles, if you want
    # to do that before the user closes the window explicitly.
    # Doesn't work with the -persist option typically used on windows.
    def close
      if @pipe
        @pipe.close
        @pipe = nil
      elsif @pid # only when parent has forked the plot handler
        Process.kill("TERM", @pid)
        Process.wait(@pid)
        @pid = nil
      else
        raise "can't close plot"
      end
      @files = nil # let tempfiles be GC-ed and deleted
    end
    
    # Send +str+ to the plot program, or, if #show has not been called yet,
    # queue the string to be sent later when #show is called.
    def command str
      command_history << str
      if @pipe
        @pipe.puts str
      else
        @command_queue << str
      end
    end

    # Start the plotting program by opening a pipe to it. Send all queued
    # commands. You can continue to send commands by calling #command.
    def show
      unless @pipe
        @pipe = IO.popen @app, "w"
        @pipe.sync = true
        while (cmd=@command_queue.shift)
          @pipe.puts cmd
        end
      end
    end
    
    # Add a data element to the plot with specified +data+ array and options
    # and, optionally, a path. If +data+ is a string, it is assumed to be a
    # expression defining a function, such as "sin(x)+1".
    def add data = [], options = nil, path = nil
      case data
      when String
        @data_stuff << [nil, [data, options].join(" "), nil]
      else
        @data_stuff << [data, options, path]
      end
    end
    
    def dump data, path = nil
      file =
        if path
          File.new(path, "w")
        else
          Tempfile.new("ruby_plot")
          ## might be better (at least on windows) to send the data
          ## inline, to avoid the "no file" errors when you try to
          ## zoom or replot
        end
      
      @files << file
          # This is here to prevent GC from collecting Tempfile object
          # and thereby deleting the temp file from disk.
      
      path = file.path

      if (data.first.first.respond_to? :join rescue false)
        data.each do |group|
          group.each do |point|
            file.puts point.join("\t")
          end
          file.puts
        end
      
      elsif (data.first.respond_to? :join rescue false) # assume one group
        for d in data
          if d.respond_to? :join
            file.puts d.join("\t")
          elsif d == nil
            file.puts
          else
            file.puts d.inspect
          end
        end
      
      elsif (data.first.respond_to? :each rescue false)
        data.each do |group|
          group.each do |point|
            file.puts point.to_a.join("\t") # to_a in case of narray
          end
          file.puts
        end
      
      else # assume one group
        for d in data
          if d.respond_to? :join
            file.puts d.join("\t")
          elsif d == nil
            file.puts
          else
            file.puts d.inspect
          end
        end
      end
      
      path
    
    ensure
      file.close unless file.closed?
    end
  end

  class Gnuplot < GenericPlot
    @@gnuplot_counter = 0
    
    # Returns an array of the form [major, minor].
    def Gnuplot.version(app)
      @version ||= {}
      @version[app] ||=
        begin
          v = `#{app} --version`.match(/gnuplot\s+(\d+)\.(\d+)/)
          v && v[1..2].map {|s| s.to_i}
        rescue
          nil
        end
    end
    
    def Gnuplot.version_at_least?(app, major_minor)
      major, minor = Gnuplot.version(app)
      major_needed, minor_needed = major_minor
      (major == major_needed and minor >= minor_needed) or
        (major > major_needed)
    end
    
    # Does the specified gnuplot executable support the 'Close' event?
    def has_working_close_event
      Gnuplot.version_at_least?(@app, [4, 3])
    end
    
    # Select the best term choice based on platform and gnuplot version.
    def best_term
      case RUBY_PLATFORM
      when /mswin32|mingw32/
        "win"
      else
        if Gnuplot.version_at_least?(@app, [4, 2])
          "wxt"
        else
          "x11"
        end
      end
    end
    
    attr_reader :uniqname
    
    def initialize(*)
      super
      @uniqname = next_uniqname
    end
    
    def next_uniqname
      "Gnuplot_#{Process.pid}_#{@@gnuplot_counter+=1}"
    end
    
    def use3d
      @plot_cmd = "splot"
    end
    
    def use2d
      @plot_cmd = "plot"
    end
    
    def plot_cmd
      @plot_cmd ||= "plot"
    end
    
    def term
      @term ||= ENV["GNUTERM"] || best_term
    end
    attr_writer :term
    
    attr_accessor :term_options
    
    def set_window_title title
      command "set term #{term} title '#{title}' #{term_options}"
    end
    alias window_title= set_window_title
    
    attr_reader :is_to_file
    
    def command str
      case str
      when /^\s*set\s+term\s+(\S+)/
        self.term = $1
        if /title\s+['"]?([^'"]*)/ =~ str
          @uniqname = $1
        end
      when /^\s*set\s+output\s/
        @is_to_file = true
      end
      super
    end
    
    def commit
      args = @data_stuff.map do |data, options, path|
        if data
          "'#{dump data, path}' #{options}"
        else
          options
        end
      end

      cmd_line = [plot_cmd, args.join(", ")].join(" ")

      command "set mouse"
      command cmd_line
    end
  end
  
  # Module for creating "fire and forget" plot windows. Instead of a plot window
  # that your main program keeps interacting with, these windows are created
  # with one specific plot and left to be closed by the user. No cleanup is
  # required.
  #
  # The functions in this module cam be accessed in two ways
  #
  #   include Plot::PlotUtils
  #   gnuplot do ... end
  #
  # or
  #
  #   Plot::PlotUtils.gnuplot do ... end
  #
  module PlotUtils
    module_function
    
    # Yields and returns the Plot instance. On unix/linux, the returned
    # plot instance can no longer be used to send more plot commands, since
    # it is just a copy of the real plot instance which is in a child process.
    # On windows, be sure not to exit immediately after calling this method,
    # or else tempfiles will be deleted before gnuplot has had a chance to read
    # them.
    def gnuplot(app=nil, &bl)
      begin
        gnuplot_fork(app, &bl)
      rescue NotImplementedError => ex
        raise unless ex.message =~ /fork/
        gnuplot_no_fork(app, &bl)
      end
    end
    
    def fork_returning_result # :nodoc:
      read_result, write_result = IO.pipe
      fork do
        read_result.close
        result_setter = proc do |r|
          write_result.write Marshal.dump(r)
          write_result.close
        end
        yield result_setter
      end
      write_result.close
      
      begin
        Marshal.load(read_result.read)
      rescue => ex
        ex ## ?
      end
    ensure
      [write_result, read_result].each do |io|
        io.close unless io.closed?
      end
    end
    
    def gnuplot_fork(app=nil, &bl) # :nodoc:
      Plot.new(app || 'gnuplot') do |plot|
        unless bl
          raise ArgumentError, "no block given"
        end
        bl[plot]
        
        if plot.is_to_file
          plot.commit
          plot.show
          plot.close
          result = plot
        
        else
          result = fork_returning_result do |result_setter|
            trap "INT" do exit end
            trap "TERM" do exit end # clean up tempfiles

            plot.command "set mouse"
              # redundant, but in some gp versions must do this
              # before the set term in the line below:
            plot.set_window_title plot.uniqname
            if plot.has_working_close_event
              plot.command "bind allwindows Close 'exit gnuplot'"
            end

            plot.commit
            result = plot.dup
            result.clear_data
            result.instance_eval {@files = nil; @pid = Process.pid}
            result_setter.call result
            plot.show

            if plot.has_working_close_event
              Process.wait # wait for gnuplot to exit
            else
              loop do
                sleep 5
                wmstate = `xprop -name #{plot.uniqname} WM_STATE 2>&1`
                break if not $?.success?
                break if wmstate[/window state:\s*withdrawn/i]
              end
            end
          end
        end

        return result
      end
    end
    
    def gnuplot_no_fork(app=nil, &bl) # :nodoc:
      # assume windows
      Plot.new("#{app || "pgnuplot.exe"} -persist") do |plot|
          # -persist is nicer on windows: supports mouse/key interaction
        bl[plot]
        if plot.is_to_file
          plot.commit
          plot.show
          plot.close
        
        else
          plot.command "bind allwindows Close 'exit gnuplot'"
          plot.command "bind allwindows 'q' 'exit gnuplot'"
          plot.commit
          plot.show
        end
      end
    end
  end

end

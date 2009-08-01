require 'tempfile'

module Plot

  def Plot.new(app = ENV['PLOTTER'] | 'gnuplot', filename = nil, &block)
  
    plot =
      case app

      when 'gnuplot'
        Gnuplot.new app, filename

      when 'matlab'
        raise "matlab not supported yet."

      else
        raise "Plot doesn't recognize '#{app}'.\n  Try 'gnuplot'."

      end
    
    if block
      plot.execute block
    else
      plot
    end
      
  end
  
  
  class GenericPlot
  
    def initialize app, filename
    
      @app = app
      @filename = filename
      
      @pipe = IO.popen @app, "w"
    
    end
    
    def command str
      @pipe.puts str
    end
    
    def dump data, path = nil
    
      file =
        if path
          File.new(path, "w+")
        else
          Tempfile.new("ruby_plot_")
        end
      
      for d in data
        file.puts d.join("\t")
      end
      
      file.close
      file.path
     
    end
    
    def execute block
      @script = []
      instance_eval &block
    end
  
  end
  
        
  class Gnuplot < GenericPlot
  
    def plot(*args)
    
      cmd_line = "plot "
      data = options = path = nil
      
      until args == []
        cmd_line << ", " if data
        data = args.shift
        options = args.shift || ""
        path = dump data
        cmd_line << "'#{path}' #{options}"
      end
      
      command cmd_line
      
    end
    
    def add data = [], options = "", path = nil
      @script << [data, options, path]
    end
    
    def clear
      @script = []
    end
    
    def show

      cmd_line = "plot "

      for data, options, path in @script
        cmd_line << ", " unless cmd_line == "plot "
        path = dump data, path
        cmd_line << "'#{path}' #{options}"
      end
      
      command cmd_line
      
    end
    
  end

end # module Plot

class Histogram
  # Number of bins.
  attr_reader :bincount
  
  # Size of each bin.
  attr_reader :binsize
  
  # Count of data points given.
  attr_reader :count
  
  # max, as given in opts, or max of data.
  attr_reader :max

  # min, as given in opts, or min of data.
  attr_reader :min
  
  # Unless false, normalize by this factor (or 1).
  attr_reader :norm
  
  # If "stats" option is present, calculate statistics in these attrs.
  attr_reader :mean, :stdev
  
  # An array of pairs of the form [bin, count]. Suitable for plotting. Bins are
  # inclusive of lower endpoint. Highest bin is inclusive of both endpoints.
  attr_reader :bins
  
  # Options as originally given.
  attr_reader :opts

  # Construct a Histogram based on +ary+ with the +opts+:
  #
  #   "bincount"  :: number of bins (default is 10)
  #
  #   "min" ::       min value (otherwise, based on data)
  #
  #   "max" ::       max value (otherwise, based on data)
  #
  #   "normalize" :: divide each bin by the total count, unless false
  #                 if numeric, scale the result by the value
  #                 (default is false)
  #
  #   "stats" ::    calculate statistics for the data set (min/stdev)
  #                 (default is false)
  #
  def initialize(ary, opts={})
    @opts = opts
    @bins = []

    ary = ary.map {|x| x.to_f}
    @count = ary.size
    
    @bincount = opts["bincount"]
    @binsize  = opts["binsize"]
    @min      = opts["min"] || ary.min
    @max      = opts["max"] || ary.max
    @norm     = opts["normalize"] || false
    @stats    = opts["stats"] || false

    if @bincount and @binsize
      raise ArgumentError, "Cannot specify both bincount and binsize"
    elsif @bincount
      @binsize = (@max-@min)/@bincount
    elsif @binsize
      @bincount = (@max-@min)/@binsize
    else
      @bincount = 10
      @binsize = (@max-@min)/@bincount
    end
    
    raise ArgumentError, "Cannot have binsize==0" if @binsize == 0
    
    @counts = Array.new(@bincount+1, 0)

    ary.each do |x|
      @counts[((x-min)/@binsize).round] += 1
    end

    return if ary.empty?
    
    if @stats
      n = ary.size.to_f
      @mean = ary.inject {|sum, x| sum + x} / n
      var = ary.inject(0) {|sum,x| sum+(x-@mean)**2} / (n-1)
      @stdev = Math::sqrt(var)
    end
    
    scale = (norm && @count != 0) ? norm/@count.to_f : 1
    @counts.each_with_index do |bin, i|
      @bins << [min + i*@binsize, bin*scale]
    end
  end
  
  def inspect
    attrs = %w{ bincount binsize count min max norm }
    attrs.concat %w{ mean stdev } if @stats
    s = attrs.map {|a| "#{a}=#{send(a)}"}.join(", ")
    "#<#{self.class}: #{s}>"
  end
end

if __FILE__ == $0
  require 'redshift/util/argos'
  
  defaults = {
    "v"             => 0
  }
  
  v=0
  optdef = {
    "bincount"      => proc {|arg| Integer(arg)},
    "binsize"       => proc {|arg| Integer(arg)},
    "min"           => proc {|arg| Float(arg)},
    "max"           => proc {|arg| Float(arg)},
    "normalize"     => proc {|arg| Integer(arg) rescue 1},
    
    "v"             => proc {v+=1},
    "plot"          => true,
    "o"             => proc {|arg| arg}
  }
  
  begin
    opts = defaults.merge(Argos.parse_options(ARGV, optdef))
  rescue Argos::OptionError => ex
    $stderr.puts ex.message
    exit
  end
  
  opts["stats"] = true if opts["v"] > 0

  histo = Histogram.new(ARGF, opts)
  
  out = histo.bins.map {|d| d.join("\t")}
  puts out
  
  if opts["v"] > 0
    $stderr.puts histo.inspect
  end
  
  if opts["plot"]
    require 'redshift/util/plot'
    extend Plot::PlotUtils
    
    gnuplot do |plot|
      outfile = opts["o"]
      if outfile
        ext = File.extname(outfile)[/[^.]+$/]
        plot.command "set term #{ext}"
        plot.command "set output #{outfile.inspect}"
      end
      plot.add histo.bins, %{w histeps title 'histogram'}
    end
    
    sleep 1 if /mswin32|mingw32/ =~ RUBY_PLATFORM
  end
end

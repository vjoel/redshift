# Manages interface to external animation process.
# Depends on:
#   gem install tkar
# See also:
#   http://tkar.rubyforge.org
class TkarDriver
  # +dragger+ is a callable object that takes (id, x, y) and should
  # move object id to (x,y)
  def initialize dragger = nil
    @dragger = dragger
    cmd =
      case RUBY_PLATFORM
      when /mswin/
        "tkar --radians 2>nul"
      else
        # Use setsid so that ^C doesn't kill it
        "setsid tkar --radians 2>/dev/null"
      end

    @pipe = IO.popen(cmd, "w+")
    yield @pipe if block_given?

    @buf = 0
    update
  end

  # never let the simulation get more than this many steps ahead
  MAX_LAG = 10
  
  # let the visualization lag by this many steps, or more
  MIN_LAG = 5

  def close
    if @pipe
      @pipe.close
      @pipe = nil
    end
  end
  
  def closed?
    return true if not @pipe or @pipe.closed?
    
    begin
      @pipe.puts " " # no-op
      @pipe.flush
    rescue Errno::EPIPE
      close
      true
    else
      @pipe.closed?
    end
  end

  def update # :yields: pipe
    return unless @pipe

    yield @pipe if block_given?

    @pipe.puts "update"
    @pipe.flush
    @buf += 1
    if @buf > MAX_LAG
      catch_up_within MIN_LAG
    end
  rescue Errno::EPIPE
    close
  end

  def catch_up_within steps
    return unless @pipe

    while @buf > steps || (steps==0 && select([@pipe],[],[],0))
        ## alternately: if steps==0, send "echo ..." and wait for ...
      case line=@pipe.gets
      when nil
        close
        return
      when /^update$/
        @buf -= 1
      when /^drag (\S+) (\S+) (\S+)/
        drag_parms = $1.to_i, $2.to_f, $3.to_f
      when /^drop/
        @dragger[*drag_parms] if @dragger
      ## TODO: handle dropping on another object
      else
        puts "tkar: #{line}"
      end
    end
  rescue Errno::EPIPE
    close
  end
end

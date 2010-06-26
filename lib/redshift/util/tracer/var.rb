require 'redshift/util/tracer/trace'

class Tracer
  # Represents the various options and controls associated with a variable
  # being traced. The #trace attr holds the actual data. The Var object
  # references the original object, and will therefore keep it from being GC-ed.
  # If you want to retain the data without the object, keep only the #trace.
  class Var
    # Type affects precision and storage size. Can be any of the following
    # strings, which are the same as the NArray scalar types:
    #
    #   "byte"   ::   1 byte unsigned integer
    #   "sint"   ::   2 byte signed integer
    #   "int"    ::   4 byte signed integer
    #   "sfloat" ::   single precision float
    #   "float"  ::   double precision float
    #
    attr_reader :type

    # Chunk size is the size of the chunks (in values, not bytes) in which
    # memory is allocated. Each chunk is a +Vector+; the list of chunks is
    # a ruby array. This only needs to be adjusted for performance tuning.
    attr_reader :chunk_size
    
    # Dimensions of each entry. A vlaue of +nil+ means scalar entries, as
    # does an empty array. A value of [d1, d2...] indicates multidimensional
    # data.
    attr_reader :dims

    # Is this var currently recording? See Tracer#stop and Tracer#start.
    attr_accessor :active

    # How many calls to #run! before trace is updated? A period of 0, 1, or
    # nil means trace is updated on each call.
    attr_accessor :period

    # Counter to check for period expiration.
    attr_accessor :counter

    # Optional code to compute value, rather than use +name+. During #run!, the
    # code will be called; if it accepts an arg, it will be passed the Var, from
    # which #key and #name can be read. If code returns nil/false, no data is
    # added to the trace.
    attr_accessor :value_getter

    # The +key+ can be either an object that has a named variable (accessed by
    # the #name attr) or some arbitrary object (in which case a value_getter
    # must be provided to compute the value).
    attr_reader :key

    # The name of the variable to access in the object.
    attr_reader :name

    # Stores the trace as a list of Vectors
    attr_reader :trace

    DEFAULT_TYPE = "float"

    DEFAULT_CHUNK_SIZE = 128

    DEFAULT_PERIOD = nil

    # The +opts+ is a hash of the form:
    #
    #   { :type => t, :chunk_size => s,:dims => nil or [d1,d2,...],
    #     :period => p }
    #
    # Strings may be used instead of symbols as the keys.
    #
    def initialize key, name, opts={}, &value_getter
      @key, @name, @value_getter = key, name, value_getter

      @type = (opts[:type] || opts["type"] || DEFAULT_TYPE).to_s
      @chunk_size = opts[:chunk_size] || opts["chunk_size"] ||
        DEFAULT_CHUNK_SIZE
      @dims = opts[:dims] || opts["dims"] || []
      @period = opts[:period] || opts["period"] || DEFAULT_PERIOD

      @period = nil unless @period.kind_of?(Integer) and @period > 1
      @counter = 0
      @active = true
      @trace = Trace.new(
        :type => type, :chunk_size => chunk_size, :dims => dims)
    end

    def run!
      return unless @active
      
      if @period
        @counter += 1
        return if @counter < @period
        @counter = 0
      end

      result =
        if (vg=@value_getter)
          case vg.arity
          when 0; vg.call
          when 1,-1; vg.call(self)
          else raise ArgumentError,
            "value_getter for #{@key}.#{@name} must take 0 or 1 arguments"
          end
        else
          @key.send @name
        end

      if result
        @trace << result
      end
    end
  end
end

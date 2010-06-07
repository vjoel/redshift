class Tracer
  begin
    require 'narray'

  rescue LoadError
    warn "Can't find narray lib;" +
      " using Array instead of NVector for trace storage."
    class Trace < Array
      def initialize(*); super(); end
    end

  else
    # A Trace is a linear store. Usually, the type of the stored data is
    # homogenous and numeric. It is optimized for appending new data at the
    # end of the store. Insertions are not efficient.
    #
    # If we have NArray, the we can use it for more compact storage than an
    # array of ruby objects. The Trace class manages a list of fixed-size
    # NVectors. Otherwise, if NArray is not available, Trace is just a ruby
    # array.
    class Trace
      include Enumerable
      
      DEFAULT_TYPE = "float"

      DEFAULT_CHUNK_SIZE = 128

      # The +opts+ is a hash of the form:
      #
      #   { :type => t, :dims => nil or [d1,d2,...], :chunk_size => s }
      #
      # Strings may be used instead of symbols as the keys.
      #
      # The +type+ is passed to NVector.new. The +chunk_size+ is the size of
      # each NVector. The +dims+ is the dimensions of each entry; default is
      # +nil+, which means scalar entries, as does an empty array.
      def initialize opts = {}
        @type = (opts[:type] || opts["type"] || DEFAULT_TYPE).to_s
        @chunk_size = opts[:chunk_size] || opts["chunk_size"] ||
          DEFAULT_CHUNK_SIZE
        @dims = opts[:dims] || opts["dims"] || []
        @index_template = @dims.map {|d| true}
        @index_template << nil
        @nvector_new_args = [@type, *@dims] << @chunk_size
        clear
      end
      
      # Clear the trace. Does not affect any state of the Var, such as
      # the period counter.
      def clear
        @chunk_list = []
        @index = @chunk_size # index of next insertion
      end

      # Iterate over values. (Note that this iteration yields the complete
      # data structure for a point in time, whereas NVector#each iterates over
      # individual numbers.)
      def each
        last = @chunk_list.last
        it = @index_template.dup
        @chunk_list.each do |chunk|
          if chunk == last and @index < @chunk_size
            @chunk_size.times do |i|
              break if i == @index
              it[-1] = i
              yield chunk[*it]
            end
          else
            @chunk_size.times do |i|
              it[-1] = i
              yield chunk[*it]
            end
          end
        end
      end
      
      def size
        (@chunk_list.size - 1) * @chunk_size + @index
      end
      
      alias length size

      def << item
        if @index == @chunk_size
          @chunk_list << NVector.new(*@nvector_new_args)
          @index = 0
        end
        @index_template[-1] = @index
        @chunk_list.last[*@index_template] = item
        @index += 1
        self
      end
      
      alias push <<
      
      # This is an inefficient, but sometimes convenient, implementation
      # of #[]. For efficiency, use the Enumerable methods, if possible, or 
      # use #to_vector. This implementation does support negative indices.
      def [](i)
        if i.abs >= size
          raise IndexError, "index out of range"
        end
        
        i %= size
        it = @index_template.dup
        it[-1] = i % @chunk_size
        @chunk_list[i / @chunk_size][*it]
      end
      
      # This is the most efficient way to manipulate the data if Enumerable
      # methods are not enough. It returns a copy of the trace data as a
      # NVector, which supports a complete set of indexed collection methods and
      # algebraic operations, including slicing, sorting, reshaping, statistics,
      # and scalar and vector math. See NArray docs for details.
      # Note that #[] works differently on NArray than the one defined above..
      def to_vector
        nva = @nvector_new_args.dup
        nva[-1] = size
        v = NVector.new(*nva)
        last = @chunk_list.last
        cs = @chunk_size
        it = @index_template.dup
        @chunk_list.each_with_index do |chunk, ci|
          base = ci * @chunk_size
          if chunk == last and @index < @chunk_size
            it[-1] = base...base+@index
            v[*it] = chunk[true, 0...@index]
          else
            it[-1] = base...base+cs
            v[*it] = chunk
          end
        end
        v
      end
      
      def inspect
        to_vector.inspect
      end
      
      def to_s
        entries.to_s
      end
    end
  end
end

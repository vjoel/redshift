module RandomDistribution

  # Base class for sequences that sample different kinds of distributions.
  # The actual PRNG must be plugged in at initialization, or else ruby's
  # global PRNG is used.
  class Sequence
    include Math
    
    class RubyGlobalGenerator
      attr_reader :seed
      
      def initialize(seed = nil)
        @seed = seed
        srand(seed) if seed
      end
      def next
        rand
      end
    end
  
    attr_reader :generator
    
    # Options are :seed and :generator.
    #
    # The :generator must either have a method #next that returns
    # a float between 0 and 1, or a method #new that returns an instance
    # that has such a #next method.
    #
    # If generator is not given, uses ruby's Kernel#rand (beware global state)
    # and the :seed option.
    #
    def initialize opt = {}
      gen = opt[:generator] || RubyGlobalGenerator
      if gen.respond_to?(:new)
        @generator = gen.new(opt[:seed])
      else
        @generator = gen
      end
    end
    
    def self.serial_count
      @count ||= 0
      @count += 1
    end
    
    # A utility method for getting a random seed.
    def self.random_seed
      Sequence.random_pool_seed ||
        ((Time.now.to_f * 1_000_000_000).to_i % 1_000_000_000) +
        Sequence.serial_count + Process.pid
    end
    
    @@have_dev_random = true # assume so until evidence to contrary
    
    def self.random_pool_seed
      ## could also get random data from net
      if @@have_dev_random
        @random_pool ||= ""
        if @random_pool.length < 4
          File.open('/dev/random') do |dr|
            if select([dr],nil,nil,0)
              @random_pool << dr.sysread(100)
            end
          end
        end
        if @random_pool.length >= 4
          @random_pool.slice!(-4..-1).unpack('L')[0]
        end
      end
    rescue SystemCallError
      @@have_dev_random = false
    end
    
    def next
      @generator.next
    end
  end
  
  class ConstantSequence < Sequence
    attr_reader :mean
    
    def initialize opt = {}
      @mean = Float(opt[:mean] || 0)
    end
    
    def next
      @mean
    end
  end
  
  class UniformSequence < Sequence
    attr_reader :min, :max
    
    def initialize opt = {}
      super
      @min = Float(opt[:min] || 0)
      @max = Float(opt[:max] || 1)
      @delta = @max - @min
    end
    
    def next
      @min + @delta*super
    end
  end
  
  class ExponentialSequence < Sequence
    attr_reader :mean
    
    def initialize opt = {}
      super
      @mean = Float(opt[:mean] || 1)
    end
  
    def next
      while (x=super) == 0.0; end
      return -log(x) * @mean
    end
  end  

  class GaussianSequence < Sequence
    attr_reader :mean, :stdev, :min, :max
    
    def initialize opt = {}
      super
      @mean = Float(opt[:mean] || 0)
      @stdev = Float(opt[:stdev] || 1)
      @min = opt[:min]; @min = Float(@min) if @min
      @max = opt[:max]; @max = Float(@max) if @max
      @nextnext = nil
    end
  
    def next
      if @nextnext
        result = @mean + @nextnext*@stdev
        @nextnext = nil
      
      else
        begin
          v1 = 2 * super - 1
          v2 = 2 * super - 1
          rsq = v1*v1 + v2*v2
        end while rsq >= 1 || rsq == 0

        fac = sqrt(-2*log(rsq) / rsq)
        @nextnext = v1*fac
        result = @mean + v2*fac*@stdev
      end
      
      if @min and result < @min
        result = @min
      elsif @max and result > @max
        result = @max
      end
      
      return result
    end
  end

  # Based on newran02:
  #
  #   Real VariLogNormal::Next(Real mean, Real sd)
  #   {
  #      // should have special version of log for small sd/mean
  #      Real n_var = log(1 + square(sd / mean));
  #      return mean * exp(N.Next() * sqrt(n_var) - 0.5 * n_var);
  #   }
  #
  class LogNormalSequence < Sequence
    attr_reader :mean, :stdev
    
    def initialize opt = {}
      @gaussian_seq = GaussianSequence.new(
        :mean   => 0,
        :stdev  => 1,
        :seed   => opt[:seed],
        :generator => opt[:generator]
      )
      
      super :generator => @gaussian_seq

      @mean = Float(opt[:mean] || 1)
      @stdev = Float(opt[:stdev] || 1)
      
      n_var = log(1 + (stdev / mean)**2)
      @sqrt_n_var = sqrt(n_var)
      @half_n_var = 0.5 * n_var
    end
    
    def next
      mean * exp(super() * @sqrt_n_var - @half_n_var)
    end
  end

  class DiscreteSequence < Sequence
    attr_reader :distrib
    
    def initialize opt = {}
      super
      @distrib = opt[:distrib] || { 0 => 1.0 }
      
      sum = @distrib.inject(0) {|sum, (pt, prob)| sum + prob}
      sum = sum.to_f # so division is ok
      
      @distrib.keys.each do |point|
        @distrib[point] /= sum
      end
    end
    
    def next
      loop do
        r = super
        @distrib.each do |point, probability|
          if r < probability
            return point
          end
          r -= probability
        end
        # repeat if failed to get a result (due to floating point imprecision)
      end
      ## this would be faster using an rbtree
    end
  end

  Constant                = ConstantSequence
  Uniform                 = UniformSequence
  Exponential             = ExponentialSequence
  Gaussian                = GaussianSequence
  Normal = NormalSequence = GaussianSequence
  LogNormal               = LogNormalSequence
  Discrete                = DiscreteSequence
end

if __FILE__ == $0
  require 'redshift/util/argos'
  
  defaults = {
    "n"     => 10,
    "d"     => Random::Uniform
  }
  
  optdef = {
    "n"     => proc {|n| Integer(n)},
    "d"     => proc {|d|
      Random.const_get(Random.constants.grep(/^#{d}/i).first)
    },
    "m"     => proc {|m| Float(m)},
    "s"     => proc {|s| Float(s)},
    "seed"  => proc {|seed| Integer(seed)},
  }

  begin
    opts = defaults.merge(Argos.parse_options(ARGV, optdef))
  rescue Argos::OptionError => ex
    $stderr.puts ex.message
    exit
  end

  seq = opts["d"].new :mean => opts["m"], :stdev => opts["s"],
        :seed => opts["seed"]
  puts (0...opts["n"]).map {seq.next}
end

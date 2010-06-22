require 'redshift/util/isaac/isaac.so'

# Adaptor class to use ISAAC with redshift/util/random distributions.
# See test/test_flow_trans.rb for an example.
class ISAACGenerator < ISAAC
  def initialize(*seeds)
    super()
    if seeds.compact.empty?
      if defined?(Random::Sequence.random_seed)
        seeds = [Random::Sequence.random_seed]
      else
        seeds = [rand]
      end
    end
    @seeds = seeds
    srand(seeds)
  end
  
  attr_reader :seeds

  alias next rand
end

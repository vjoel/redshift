require 'redshift'
include RedShift

# Tests numerical differentiation.
class DerivativeTestComponent < Component
  flow do
    diff   "     t' = 1      "
    alg    "     u  = sin(t) "
    alg    "   sdu  = cos(t) " # symbolic derivative
    derive "   ndu  = u'     " # numerical derivative
    alg    "   err  = sdu - ndu "
  end

  def assert_consistent test
    test.assert_in_delta(0, err, 0.02)
  end
end

require 'test/unit'

class TestDerivative < Test::Unit::TestCase
  
  def setup
    @world = World.new
  end
  
  def teardown
    @world = nil
  end
  
  def test_derivative
    c = @world.create(DerivativeTestComponent)
    @world.evolve 100
    c.assert_consistent self
  end
end

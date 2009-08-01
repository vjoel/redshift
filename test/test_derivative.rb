require 'redshift'
include RedShift

# Tests numerical differentiation.
class DerivativeTestComponent < Component
  flow do
    diff   "     t' = 1 "

    alg    "     u  = sin(t) "
    alg    "   sdu  = cos(t) " # symbolic derivative
    derive "   ndu  = (u+5)' " # numerical derivative -- expr OK
    diff   " nindu' = ndu    " # numerical integral of ndu
    diff   "   niu' = u      " # numerical integral of u
    derive " ndniu  = niu'   " # numerical derivative of niu
    
    alg    "   err  = sdu - ndu "
    alg    " e_ndni = ndniu - u "
    alg    " e_nind = nindu - u "
  end

  def assert_consistent test
    test.assert_in_delta(0, err, 0.025)
    test.assert_in_delta(0, e_ndni, 0.0025)
    test.assert_in_delta(0, e_nind, 0.2)
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
    @world.evolve 100 do
      c.assert_consistent self
    end
  end
end

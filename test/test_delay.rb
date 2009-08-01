require 'redshift'
include RedShift

# Tests delay of continuous var.
class DelayTestComponent < Component
  constant :pi => Math::PI
  constant :d => 0.2
  @@d2 = d2 = 0.1

  flow do
    diff   "       t' = 1      "
    alg    "       u  = sin(t*pi/2) "
    alg    " shift_u  = sin((t-(d+#{d2}))*pi/2) " # u shifted by d+d2
    delay  " delay_u  = u + 1 ", :by => "d+#{d2}" # u+1 delayed by d+d2
    alg    "     err  = shift_u - (delay_u - 1)"
  end

  constant :new_d => 0.5  # change this to see how varying delay works
  constant :t_new_d => 5.0
  transition do
    guard "t > t_new_d && d != new_d"
    reset :d => "new_d"
  end

  def assert_consistent test
    return if t <= d + @@d2
    return if t >= t_new_d and t <= t_new_d + new_d
    test.assert_in_delta(0, err, 1.0E-10)
  end
end

require 'test/unit'

class TestDelay < Test::Unit::TestCase
  
  def setup
    @world = World.new
  end
  
  def teardown
    @world = nil
  end
  
  def test_derivative
    c = @world.create(DelayTestComponent)
    @world.evolve 100 do
      c.assert_consistent self
    end
  end
end

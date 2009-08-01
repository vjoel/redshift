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
    
    delay  " zdelay_t  = t ", :by => 0.3
  end

  constant :new_d => 0.5  # change this to see how varying delay works
  constant :t_new_d => 5.0
  transition do
    guard "t > t_new_d && d != new_d"
    reset :d => "new_d"
  end

  def assert_consistent test
    if t > d + @@d2 and (t < t_new_d or t > t_new_d + new_d)
      test.assert_in_delta(0, err, 1.0E-10)
    end
    
    if t >= 0.3
      test.assert_in_delta(t - 0.3, zdelay_t, 1.0E-10)
      # zdelay will be evaluated after t (alphabetical), so this assertion
      # breaks before the fix in 1.2.19. (At rk_level==3, evaluating t
      # writes to t's value_0, which is what teh evaluation of zdelay is
      # trying to capture.
    end
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

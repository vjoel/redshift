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
      # writes to t's value_0, which is what the evaluation of zdelay is
      # trying to capture.
    end
  end
end

class StateChanger < Component
  state :Normal, :Delayed
  start Normal
  constant :eps => 1e-10
  
  flow Normal, Delayed do
    diff  " x' = 1 "
  end
  
  flow Delayed do
    delay " xd = x ", :by => "1.0"
  end
  
  debug = false
  
  transition Normal => Delayed do
    guard " x >= 2 - eps && x < 2.2 "
    action {debug_output} if debug
  end
    
  transition Delayed => Normal do
    guard " x >= 5 - eps && x < 5.2 "
    action {debug_output} if debug
  end
  
  transition Normal => Delayed do
    guard " x >= 7 - eps && x < 7.2 "
    action {debug_output} if debug
  end
    
  transition Delayed => Normal do
    guard " x >= 9 - eps && x < 9.2 "
    action {debug_output} if debug
  end
  
  def assert_consistent test
    if x <= 2 + eps
      # at 2, nothing has been put in buffer yet
      test.assert_in_delta(0, xd, 1e-10)
    elsif x <= 3 - eps
      # buffer warm up
      test.assert_in_delta(2, xd, 1e-10)
    elsif x <= 5 - eps
      test.assert_in_delta(x-1, xd, 1e-10)
    elsif x <= 7 - eps
      # stale data
      test.assert_in_delta(4, xd, 1e-10)
    elsif x <= 8 - eps
      # still consuming old data -- not sure this is right, but it
      # is simple -- see comments in delay.rb
      test.assert_in_delta(x-3, xd, 1e-10)
    elsif x <= 9 - eps
      test.assert_in_delta(x-1, xd, 1e-10)
    else
      test.assert_in_delta(8, xd, 1e-10)
    end
  end
  
  def debug_output
    p self, self.xd_buffer_data
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
  
  def test_delay
    c = @world.create(DelayTestComponent)
    @world.evolve 100 do
      c.assert_consistent self
    end
  end
  
  def test_persist
    c = @world.create(DelayTestComponent)
    @world.evolve 50
    
    w = Marshal.load(Marshal.dump(@world))
    a = w.grep(DelayTestComponent)
    assert_equal(1, a.size)
    c2 = a[0]
    
    w.evolve 100 do
      c2.assert_consistent self
    end
  end
  
  def test_state_change
    c = @world.create(StateChanger)
    @world.evolve 10.0 do
      c.assert_consistent self
      #puts "%5.3f: %5.3f" % [c.x, c.xd]
    end
  end
end

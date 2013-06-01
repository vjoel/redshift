require "redshift"
include RedShift

class A < Component
  continuous :ns_x
  strictly_continuous :x

  constant :ns_k
  strictly_constant :k => 6.78

  flow do
    diff " x' = 2*x "
  end
end

class B < Component
  strict_input :y
  transition Enter => Exit do
    name "t"
    guard "y > 5"
  end
end

class Dummy < Component
  state :S, :T, :U
  setup do
    start S
  end
  
  flow S do
    diff "time' = 1"
  end
  
  transition S => T do
    guard "time > 0"
    reset :time => 0 # so we do it again next timestep
  end
  
  transition T => U, U => S
end

# From test_strict_continuity.rb
class SCWorld < World
  def num_checks
    @num_checks ||= Hash.new do |h,comp|
      h[comp] = Hash.new do |h1,trans|
        h1[trans] = 0
      end
    end
  end
  
  def hook_eval_guard(comp, guard, enabled, trans, dest)
    num_checks[comp][trans.name] += 1
  end
end

#-----#

require 'minitest/autorun'

class TestConnectStrict < Minitest::Test

  def setup
    @world = SCWorld.new
    @world.time_step = 0.1
    @a = @world.create(A) {|a| a.x = 1 }
    @b = @world.create(B)
    @world.create(Dummy)
  end
  
  def teardown
    @world = nil
  end
  
  # can connect strict_input *only* to strict var/const
  def test_not_connectable
    assert_raises(StrictnessError) do
      @b.port(:y) << @a.port(:ns_x)
    end
    assert_raises(StrictnessError) do
      @b.port(:y) << @a.port(:ns_k)
    end
  end
  
  # can't disconnect strict_input that has been connected
  def test_disconnect
    @b.port(:y) << nil # ok
    @b.port(:y) << @a.port(:x)
    assert_raises(StrictnessError) do
      @b.port(:y) << nil
    end
  end
  
  # can't connect to a different component
  def test_reconnect_comp
    @b.port(:y) << @a.port(:x)
    @b.port(:y) << @a.port(:x) # ok
    assert_raises(StrictnessError) do
      @b.port(:y) << @world.create(A).port(:x)
    end
  end

  # can't connect to a different var in same component
  def test_reconnect_var
    @b.port(:y) << @a.port(:x)
    assert_raises(StrictnessError) do
      @b.port(:y) << @a.port(:k)
    end
  end
  
  # can reconnect if value is the same
  def test_reconnect_same_value
    a = @world.create(A) do |a|
      a.x = a.k = 12.34
    end
    @b.port(:y) << a.port(:x)
    #assert_nothing_raised
    @b.port(:y) << a.port(:k)
  end
  
  # One check per step, despite the Dummy
  def test_strict_guard
    @b.port(:y) << @a.port(:x)
    prev = nil
    @world.evolve 2 do
      if @b.state == Enter
        if prev
          assert_equal(prev + 1, @world.num_checks[@b]["t"])
        end
        prev = @world.num_checks[@b]["t"]
      end
    end
  end
end

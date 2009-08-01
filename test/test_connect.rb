require "redshift"
include RedShift

class A < Component
  continuous :x
  constant :k => 6.78
  flow do
    diff " x' = 2*x "
  end
end

class B < Component
  input :y
  flow do
    alg " z = y+1 "
  end
  transition Enter => Exit do
    guard "y < 0"
  end
end

#-----#

require 'test/unit'

class TestConnect < Test::Unit::TestCase

  def setup
    @world = World.new
    @world.time_step = 0.1
    @a = @world.create(A)
    @b = @world.create(B)
  end
  
  def teardown
    @world = nil
  end
  
  def test_unconnected
    assert_raises(UnconnectedInputError) do
      @b.y
    end
    
    assert_raises(NoMethodError) do
      @b.y = 1.23
    end

    assert_raises(UnconnectedInputError) do
      @world.evolve 1
      ## leaves alg flows in bad state, so end the test here
    end
  end

  def test_unconnected1
    assert_raises(UnconnectedInputError) do
      @b.z
      ## leaves alg flows in bad state, so end the test here
    end
  end
    
  def test_not_connectable
    assert_raises(TypeError) do
      @a.port(:x) << @b.port(:y)
    end
    assert_raises(TypeError) do
      @a.connect(:x, @b, :y)
    end
  end
  
  def test_connect
    @b.connect(:y, @a, :x)
    @a.x = 4.56
    
    assert_equal(@a.x, @b.y)
    assert_equal(@b.y+1, @b.z)
    @world.evolve 1 do
      assert_equal(@a.x, @b.y)
      assert_equal(@b.y+1, @b.z)
    end
    
    # reconnect to different var (actually a constant)
    @b.connect(:y, @a, :k)

    assert_equal(@a.k, @b.y)
    assert_equal(@b.y+1, @b.z)
    @world.evolve 1 do
      assert_equal(@a.k, @b.y)
      assert_equal(@b.y+1, @b.z)
    end
    
    # disconnect
    @b.disconnect(:y)
    
    # nothing raised:
    @b.disconnect(:y)
    
    # reconnect to different component (using ports)
    @a = @world.create(A)
    @b.port(:y) << @a.port(:x)

    @a.x = 7.89
    
    assert_equal(@a.x, @b.y)
    assert_equal(@b.y+1, @b.z)
    @world.evolve 1 do
      assert_equal(@a.x, @b.y)
      assert_equal(@b.y+1, @b.z)
    end
  end
  
  def test_reflection
    @b.connect(:y, @a, :x)
    
    assert_equal(@a.port(:x), @b.port(:y).source)
    assert_equal(@a, @b.port(:y).source_component)
    assert_equal(:x, @b.port(:y).source_variable)

    assert_equal(@a, @a.port(:x).component)
    assert_equal(:x, @a.port(:x).variable)
  end
  
  def test_disconnect
    @b.connect(:y, @a, :x)
    @b.disconnect(:y)
    assert_equal(nil, @b.port(:y).source)

    @b.port(:y).disconnect
    assert_equal(nil, @b.port(:y).source)

    @b.port(:y) << nil
    assert_equal(nil, @b.port(:y).source)

    assert_raises(UnconnectedInputError) do
      @b.y
    end
  end
end

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
  input :yy # usually unused, so doesn't need to be connected
  link :other => B
  
  flow do
    alg " z = y+1 "
    alg " w = y + yy "
    alg " u = other.y "
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
    end

    assert_raises(UnconnectedInputError) do
      @b.z
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
    
    assert_raises(UnconnectedInputError) do
      @b.z
    end

    assert_raises(UnconnectedInputError) do
      @b.y
    end

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
  
  def test_connect_to_input
    b2 = @world.create(B)
    @b.port(:y) << @a.port(:x)
    b2.port(:y) << @b.port(:y)
    @a.x = 3.456
    assert_equal(@b.y, b2.y)
    assert_equal(@a.x, b2.y)
    assert_equal(b2.y+1, b2.z)
  end
  
  def test_connect_input_chain
    b = (0..99).map {@world.create(B)}
    (0..98).each do |i|
      b[i+1].port(:y) << b[i].port(:y)
    end
    b[0].port(:y) << @a.port(:x)

    @a.x = 42.4242
    assert_equal(@a.x, b[99].y)
    assert_equal(@a.x, b[0].y)
    
    old_b_50 = b[50]
    b[50] = @world.create(B)
    b[50].port(:y) << b[49].port(:y)
    b[51].port(:y) << b[50].port(:y)

    @a.x = 987.789
    assert_equal(@a.x, b[99].y)
    assert_equal(@a.x, b[0].y)
    assert_equal(@a.x, old_b_50.y)
  end
  
  def make_circle n
    b = (0...n).map {@world.create(B)}
    n.times do |i|
      b[i].port(:y) << b[(i+1)%n].port(:y)
    end
    b
  end
    
  def test_connect_input_circular
    [1, 2, 3, 10].each do |n|
      b = make_circle(n)
      assert_raises(RedShift::CircularDefinitionError) do
        b[0].y
      end
    end
  end
  
  def test_connect_input_flow
    b = (0..5).map {@world.create(B)}
    (0..4).each do |i|
      b[i+1].port(:y) << b[i].port(:y)
    end
    b[0].port(:y) << @a.port(:x)
        
    @b.port(:y) << @a.port(:x) # ust so guard doesn't find y unconn.

    @a.x = 1.0
    assert_equal(@a.x, b[5].y)
    assert_equal(@a.x, b[0].y)

    @world.evolve 10
    assert_equal(@a.x, b[5].y)
    assert_equal(@a.x, b[0].y)
  end

  def test_connect_input_multiple
    @b.port(:y) << @a.port(:x)
    @b.port(:yy) << @b.port(:y) # Can connect to another var in self!
    @a.x = 1.0
    assert_equal(@a.x*2, @b.w)
  end
  
  def test_linked_input
    @a.x = 99.876
    
    @b.other = @world.create(B)
    @b.other.port(:y) << @a.port(:k)

    assert_equal(@b.other.y, @a.k)
    assert_equal(@b.other.y, @b.u)
  end
  
  ### test guards and interaction with other flows
  
  def test_marshal
    @a.x = -3.21
    @b.port(:y) << @a.port(:x)
    assert_equal(@a.x, @b.y)

    world2 = Marshal.load(Marshal.dump(@world))
    a = world2.grep(A).first
    b = world2.grep(B).first
    assert_equal(a.x, b.y)
    p a, b
  end
  
  def test_ports_change_when_reconnect
    return
    b2.port(:y) << @a.port(:x)
    puts "### #{ b2.z }"
    b2.port(:y) << @b.port(:y)
    puts "### #{ b2.z }"

    p b2.port(:y)
    p b2.y_src_comp
    puts
    
    p b2.port(:y) ### did not update!
    p b2.y_src_comp # ok!
    puts

    b2.port(:y) << nil
    p b2.port(:y)
    p b2.y_src_comp
    puts
    
  end
end

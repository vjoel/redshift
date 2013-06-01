require 'redshift'

include RedShift

RedShift.with_library do |library|
  require "redshift/target/c/flow/buffer"
  library.define_buffer
end

require 'minitest/autorun'

class TestBuffer < Minitest::Test

  class T < Component
    RedShift.with_library do
      shadow_attr_accessor :b => "RSBuffer b"
    end
  end
  
  def setup
    @world = World.new
    @t = @world.create(T)
  end
  
  def teardown
    @world = nil
  end
  
  def test_accessor
    a = [1.0, 2.0, 3.0, 4.0]
    @t.b = a
    assert_equal(a, @t.b)
  end
  
  def test_empty
    assert_equal([], @t.b)
  end
  
  def test_marshal
    t2 = Marshal.load(Marshal.dump(@t))
    assert_equal(@t.b, t2.b)
  end
  
  def make_garbage
    5.times do
      @world = World.new
      @world.create(T)
    end
  end
    
  def test_gc
    make_garbage
    n1 = ObjectSpace.each_object(T) {}
    GC.start
    n2 = ObjectSpace.each_object(T) {}
    assert(n2 < n1)
  end
end

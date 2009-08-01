require 'redshift/queue'
require 'test/unit'

# Test queue class outside of simulation using mocked World and
# Component classes.
class TestQueueAlone < Test::Unit::TestCase
  class World
    attr_accessor :clock, :discrete_step
  end
  class Component
    attr_accessor :world, :awake
    def inc_queue_ready_count
      @awake = true
    end
    def dec_queue_ready_count
    end
  end
  
  def setup
    @w = World.new
    @w.clock = 0.0
    @w.discrete_step = 0
    @c = Component.new
    @c.world = @w
    @q = RedShift::Queue.new @c
  end
  
  def test_fifo
    3.times do |i|
      @q.push i
      @w.discrete_step += 1
    end
    
    a = []
    3.times do
      a << @q.pop
    end
    
    assert_equal([0,1,2], a)
  end
  
  def test_unpop
    @q.push 1
    x = @q.pop
    @q.unpop x
    assert_equal(x, @q.pop)
  end
  
  def test_simultaneous_entries
    @w.clock = 1.23
    @w.discrete_step = 42
    a = [1,2,3]
    a.each do |x|
      @q.push x
    end
    
    head = @q.pop
    assert_equal(a, head)
    @q.unpop head
    
    @w.discrete_step += 1
    @q.push "some stuff"
    assert_equal(a, @q.pop)
  end
  
  def test_unpop_partial
    @w.clock = 1.23
    @w.discrete_step = 42
    a = [1,2,3]
    a.each do |x|
      @q.push x
    end
    
    head = @q.pop
    head.shift
    @q.unpop head
    
    head = @q.pop
    assert_equal([2,3], head)
    assert_equal(RedShift::SimultaneousQueueEntries, head.class)
    head.shift
    @q.unpop head
    
    head = @q.pop
    assert_equal(3, head)
  end
  
  def test_wake
    @c.awake = false
    @q.push 1
    assert_equal(true, @c.awake)
  end
  
  def test_match_empty_queue
    assert_equal(false, @q.head_matches(Object))
  end
    
  def test_match_one_entry
    @q.push("foo")
    assert(@q.head_matches(     )) 
    assert(@q.head_matches( /o/ ))
    assert(@q.head_matches( String, /o/, proc {|x| x.kind_of?(String)} ))
    
    assert_equal(false, @q.head_matches( /z/    ))
    assert_equal(false, @q.head_matches( Symbol ))
    assert_equal(false, @q.head_matches( proc {false} ))
  end
  
  def test_match_simultaneous_entries
    @q.push "foo"
    @q.push "bar"
    assert(@q.head_matches( /foo/ ))
    assert(@q.head_matches( /bar/ ))
  end
end

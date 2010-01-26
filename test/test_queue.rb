require 'redshift'
require 'test/unit'

class TestQueue < Test::Unit::TestCase
  class Receiver < RedShift::Component
    queue :q
    transition Enter => Exit do
      wait :q
    end
  end
  
  class Sender < RedShift::Component
    link :receiver => RedShift::Component
    flow {diff "t'=1"}
    transition Enter => Exit do
      guard "t>1"
      action do 
        receiver.q << "hello"
      end
    end
  end
  
  def setup
    @world = RedShift::World.new
    @s = @world.create(Sender)
    @r = @world.create(Receiver)
    @s.receiver = @r
  end
  
  def test_msg_received
    @world.evolve 0.9
    assert_equal(RedShift::Component::Enter, @r.state)
    assert(@world.queue_sleep[@r])
    @world.evolve 0.2
    assert_equal(RedShift::Component::Exit, @r.state)
    assert_equal("hello", @r.q.pop)
  end
end

class TestQueueAndStrict < Test::Unit::TestCase
  class Receiver < RedShift::Component
    queue :q
    strictly_continuous :x
    transition Enter => Exit do
      guard "x>0"
    end
    transition Enter => Exit do
      wait :q
    end
  end
  
  class Sender < RedShift::Component
    link :receiver => RedShift::Component
    flow {diff "t'=1"}
    state :S1
    transition Enter => S1 do
      guard "t>1"
      # this transition gives receiver a chance to go into strict sleep,
      # if that bug exists in redshift
    end
    transition S1 => Exit do
      action do 
        receiver.q << "hello"
      end
    end
  end
  
  def setup
    @world = RedShift::World.new
    @s = @world.create(Sender)
    @r = @world.create(Receiver)
    @s.receiver = @r
  end
  
  def test_msg_received
    @world.evolve 0.9
    assert_equal(RedShift::Component::Enter, @r.state)
    while @r.state == RedShift::Component::Enter do
      # Can't be in queue sleep because of the x>0 guard.
      assert(!@world.queue_sleep[@r])
      @world.run 1
    end
    
    # in 1 step, @r should *both* receive the message and exit,
    # which shows that it did not go into strict sleep after the first
    # pass thru discrete update
    assert_equal(RedShift::Component::Exit, @r.state)
    assert_equal("hello", @r.q.pop)
  end
end

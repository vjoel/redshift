# test chains of asymmetric sync
# when guard not enabled at root, ...

# test chains of symmetric sync

require 'redshift'
require 'test/unit'

class DebugSyncWorld #< RedShift::World
  def hook_begin
    puts "===== begin discrete update ====="
  end
  
  def hook_enter_sync_phase
    puts "enter sync phase"
  end
  
  def hook_can_sync comp, can_sync
    puts "    #{comp.inspect}: can_sync=#{can_sync.inspect}"
  end
  
  def hook_sync_step syncers, changed
    puts "  sync step, changed=#{changed.inspect}"
    puts "  syncers = #{syncers.inspect}"
  end
end

class TestSync < Test::Unit::TestCase
  class Relay < RedShift::Component
    link :next
    
    transition Enter => Exit do
      sync :next => :e
      event :e
    end
  end
  
  class Emitter < RedShift::Component
    transition Enter => Exit do
      event :e
    end
  end
  
  class Emitter_f < RedShift::Component
    transition Enter => Exit do
      event :f
    end
  end
  
  class Ground < RedShift::Component
    link :next
    
    transition Enter => Exit do
      sync :next => :e
    end
  end
  
  class EmitTwo < RedShift::Component
    state :EmitE, :EmitF, :EmitEF
    transition Enter => EmitE do
      event :e
    end
    transition EmitE => EmitF do
      event :f
    end
    transition EmitF => EmitEF do
      event :e, :f
    end
  end
  
  class SyncTwo < RedShift::Component
    link :next
    setup {self.next = create(EmitTwo)}
    transition Enter => Exit do
      sync :next => :e
      sync :next => :f
      action do
        @worked = (self.next.state == EmitTwo::EmitF)
      end
    end
    attr_reader :worked
  end
  
  class SyncRetry < RedShift::Component
    state :Ok
    link :next
    setup {self.next = nil}
    transition Enter => Exit do
      sync :next => :no_such_event
    end
    transition Enter => Ok
  end
  
  def setup
    @w = RedShift::World.new
  end
  
  def test_sync_self
    r = @w.create Relay
    r.next = r
    g = @w.create Ground
    @w.run 1
    assert_equal(RedShift::Component::Exit, r.state)
    assert_equal(RedShift::Component::Enter, g.state)
  end
  
  def test_sync_nil
    r = @w.create Relay
    r.next = nil
    @w.run 1
    assert_equal(RedShift::Component::Enter, r.state)
  end
  
  def test_sync_no_event
    r = @w.create Relay
    r.next = @w.create Relay
    @w.run 10
    assert_equal(RedShift::Component::Enter, r.state)
  end
  
  def test_sync_wrong_event
    r = @w.create Relay
    r.next = @w.create Emitter_f
    @w.run 10
    assert_equal(RedShift::Component::Enter, r.state)
  end
  
  def test_sync_two_events
    s2 = @w.create(SyncTwo)
    assert_equal(nil, s2.worked)
    @w.run 1
    assert_equal(true, s2.worked)
  end
  
  def test_cyclic
    a = (0..4).map do
      @w.create Relay
    end
    
    # connect them in an order different from creation order
    a[4].next = a[3]
    a[3].next = a[1]
    a[1].next = a[2]
    a[2].next = a[0]
    a[0].next = a[4]
    
    @w.run 1
    a.each do |relay|
      assert_equal(RedShift::Component::Exit, relay.state)
    end
  end
  
  def test_acyclic
    a = (0..4).map do
      @w.create Relay
    end
    
    # connect them in an order different from creation order
    a[4].next = a[3]
    a[3].next = a[1]
    a[1].next = a[2]
    a[2].next = a[0]
    a[0].next = nil
    
    @w.run 1
    a.each do |relay|
      assert_equal(RedShift::Component::Enter, relay.state)
    end
    
    emitter = @w.create Emitter
    a[0].next = emitter
    
    @w.run 1
    (a + [emitter]).each do |relay|
      assert_equal(RedShift::Component::Exit, relay.state)
    end
  end
  
  # see also examples/sync-retry.rb
  def test_sync_retry
    c = @w.create SyncRetry
    @w.run 1
    assert_equal(SyncRetry::Ok, c.state)
  end
end

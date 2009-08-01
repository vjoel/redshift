#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

=begin

Tests events with inheritance.

=end

class Super < Component
  state :S1
  transition Enter => S1 do
    event :e1 => 1
  end
end

class Sub < Super
  state :S2
  transition S1 => S2 do
    event :e2 => 2
  end
end

class EventTestComponent < Component
  link :sub => Sub
  state :T1, :T2
  setup {@result = []; self.sub = create(Sub)}
  transition Enter => T1 do
    guard :sub => :e1
    action {@result << sub.e1}
  end
  transition T1 => T2 do
    guard :sub => :e2
    action {@result << sub.e2}
  end

  def assert_consistent test
    test.assert_equal([1,2], @result)
  end
end

#-----#

require 'test/unit'

class TestInheritEvent < Test::Unit::TestCase
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_event
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= EventTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    @world.run
    
    for t in testers
      t.assert_consistent self
    end
  end
end

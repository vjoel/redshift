#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

class StateTestComponent < Component
end

# repeating a state declaration is an error

class State_Duplicate < StateTestComponent
  state :A
  def assert_consistent test
    c = Class.new(self.class)
    class << self
      undef_method :assert_consistent
    end
    test.assert_exception(RuntimeError) {
      c.state :A
    }
  end
end

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestInheritState < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.01 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_state
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= StateTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    
#    @world.run 1000 do
#      testers.each { |t| t.assert_consistent self }
#    end
  end
end

END {
  RUNIT::CUI::TestRunner.run(TestInheritState.suite)
}

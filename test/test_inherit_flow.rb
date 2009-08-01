#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

#-- Flow-specific test classes --#

class FlowTestComponent < Component
  def initialize(*args)
    super
    @start_time = world.clock
  end
end

#     ------------------------
#     Per equation granularity

class Flow_1 < FlowTestComponent
  flow { alg "x = 0", "y = 1", "z = 2" }
end

class Flow_1_1 < Flow_1
  flow { alg "x = 3" }        # override one of several flows
  def assert_consistent test
    test.assert_equal([3,1,2], [x,y,z])
  end
end

class Flow_1_2 < Flow_1
  flow { alg "w = 4" }        # add a new, unrelated flow
  def assert_consistent test
    test.assert_equal([0,1,2,4], [x,y,z,w])
  end
end

class Flow_1_2_1 < Flow_1_2
  flow { alg "w = 5" }        # ...and override it in a subclass
  def assert_consistent test
    test.assert_equal([0,1,2,5], [x,y,z,w])
  end
end

#     ----------------------------------
#     Overriding the type of an equation

class Flow_2 < FlowTestComponent
  flow { alg "x = 0" }
end

class Flow_2_1 < Flow_2
  defaults { @x = 0 }
  flow { diff "x' = 1" }
  def assert_consistent test
    test.assert_equal_float(world.clock - @start_time, x, 0.00001)
  end
end

class Flow_2_1_1 < Flow_2_1
  flow { alg "x = -1" }
  def assert_consistent test
    test.assert_equal_float(-1, x, 0.00001)
  end
end

#     ---------------------
#     Per state granularity

class Flow_3 < FlowTestComponent
  state :S1, :S2
  
  defaults { @x = 0 }
  attr_reader :x
  
  flow S1 do diff "x'=1" end
  flow S2 do diff "x'=-1" end
  
  transition Enter => S1
  transition S1 => S2 do guard {x >= 1} end
  transition S2 => S1 do guard {x <= 0} end
  
  def assert_consistent test
    test.assert_equal_float(0.5, x, 0.5 + world.time_step)
  end
end

class Flow_3_1 < Flow_3
  flow S2 do diff "x'=1" end        # override in just one state
  
  transition Enter => S1
  transition S1 => S2 do guard {x >= 1} end
  transition S2 => S1 do guard {x <= 0} end
  
  def assert_consistent test
    test.assert(state == S2 || world.clock <= 1)
  end
end

## other kinds of alg and diff flows (cached-alg, euler, cflow, etc.)

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestInheritFlow < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_flow
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= FlowTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 100
    testers.each { |t| t.assert_consistent self }
  end
end

END {
  Dir.mkdir "tmp" rescue SystemCallError
  Dir.chdir "tmp"

  RUNIT::CUI::TestRunner.run(TestInheritFlow.suite)
}

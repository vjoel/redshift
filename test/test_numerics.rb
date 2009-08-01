#!/usr/bin/env ruby

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

require 'redshift/redshift'

include RedShift

class Timer < Component
  attr_accessor :x
  flow { diff " x' = 1 " }
end

class TestNumerics < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
      
  end
  
  def teardown
    @world = nil
  end
  
  def test_rational
    c = @world.create(Timer) {self.x = 1/2}
    @world.run 100
    assert_equal_float(10.5, c.x, 0.000001)
  end
end

END {
  RUNIT::CUI::TestRunner.run(TestNumerics.suite)
}

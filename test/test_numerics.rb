#!/usr/bin/env ruby

require 'mathn' # Use rationals for 1/2 etc.

require 'test/unit'

require 'redshift'

include RedShift

class Timer < Component
  attr_accessor :x
  flow { diff " x' = 1 " }
end

class TestNumerics < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.1
  end
  
  def teardown
    @world = nil
  end
  
  def test_rational
    c = @world.create(Timer) { |timer| timer.x = 1/2}
    @world.run 100
    assert_in_delta(10.5, c.x, 0.000001)
  end
end

## should test NaN, Inf, precision, etc.

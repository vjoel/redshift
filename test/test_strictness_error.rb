#!/usr/bin/env ruby

require 'redshift'

include RedShift

require 'test/unit'

class TestStrictnessError < Test::Unit::TestCase

  class T < Component

    strictly_continuous :x
    continuous :y
    link :lnk => T

    flow {
      alg "x = lnk.y+1"
    }

  end
  
  def test_strictness_error
    assert_raises(RedShift::StrictnessError) do
      World.new
    end
  end

end

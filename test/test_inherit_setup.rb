#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

#-- Setup and default-specific test classes --#

class A; end
class B < A; end

class SetupTestComponent < Component
  attr_reader :x, :y, :z, :xx, :yy, :zz, :other

  setup {@x = 0; @y = 1; @other = make_other}
  defaults {@xx = 0; @yy = 1}
  
  def make_other  # see inherit.txt
    A.new
  end

end

class Setup_1 < SetupTestComponent

  setup {@y = 2; @z = 3}
  defaults {@yy = 2; @zz = 3}

  def make_other
    B.new
  end

end

#-----#

require 'test/unit'

class TestInheritSetup < Test::Unit::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_setup
    t = @world.create(Setup_1)
    assert_equal([0,2,3], [t.x,t.y,t.z])
    assert_equal([0,2,3], [t.xx,t.yy,t.zz])
    assert_equal(B, t.other.class)
  end
end

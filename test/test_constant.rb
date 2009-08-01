#!/usr/bin/env ruby

require 'redshift'

include RedShift

class ConstantTestComponent < Component
  def finish test
  end
  
  constant :k
  strictly_constant :ks
  
  link :other => ConstantTestComponent
  
  state :HasOther, :Stop
  
  transition Enter => HasOther do
    guard "other"
  end
  
  flow HasOther do
    diff "x' = other.k + k + other.ks + ks"
    diff "t' = 1"
    ###diff "k' = 1" # should error gracefully
  end
  
  transition HasOther => Stop do
    guard "t >= 1"
    action do
      @y = other.k + k + other.ks + ks
    end
    ### reset :k => proc {k+1} # should this work?
  end
  
  def assert_consistent test
    if t >= 1
      test.assert_in_delta(44, x, 1E-10)
      test.assert_equal(44, @y)
    end
  end
end

#-----#

require 'test/unit'

class TestConstant < Test::Unit::TestCase
  
  def setup
    @world = World.new
  end
  
  def teardown
    @world = nil
  end
  
  def test_constant
    comp1 = @world.create(ConstantTestComponent) do |c1|
      c1.k = 1.0
      c1.ks = 10.0
    end
    
    comp2 = @world.create(ConstantTestComponent) do |c2|
      c2.k = 3.0
      c2.ks = 30.0
    end
    
    comp1.other = comp2
    testers = [comp1, comp2]
        
    @world.run 20
    comp1.assert_consistent self
  end
end


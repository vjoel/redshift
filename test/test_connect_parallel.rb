require "redshift"
include RedShift

class A < Component
  input :in
  continuous :x => 1
  link :comp
  
  state :T
  
  flow T do
    diff " x' = in "
  end
  
  transition Enter => T do
    reset :comp => nil
    connect :in => proc {comp.port(:x)}
  end
end

#-----#

require 'minitest/autorun'

class TestConnect < Minitest::Test

  def setup
    @world = World.new
    @world.time_step = 0.001
    @a0 = @world.create(A)
    @a1 = @world.create(A)
    @a0.comp = @a1
    @a1.comp = @a0
  end
  
  def teardown
    @world = nil
  end
  
  def test_evolve
    @world.evolve 1
    [@a0, @a1].each do |a|
      assert_in_delta(Math::E, a.in, 1.0e-12)
      assert_equal(nil, a.comp)
    end
  end
end

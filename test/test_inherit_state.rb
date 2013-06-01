require 'redshift'

include RedShift

class StateTestComponent < Component
end

class State_Inherit < StateTestComponent
  class Sub < self
  end
  state :A, :B, :C
  link :sub => Sub
  
  def assert_consistent test
    test.assert_equal(self.states, create(Sub).states)
  end
end

# repeating a state declaration is an error

###class State_Duplicate < StateTestComponent
###  state :A
###  def assert_consistent test
###    c = Class.new(self.class)
###    class << self
###      undef_method :assert_consistent
###    end
###    test.assert_exception(RuntimeError) {
###      c.state :A
###    }
###  end
###end

#-----#

require 'minitest/autorun'

class TestInheritState < Minitest::Test
  
  def setup
    @world = World.new
    @world.time_step = 0.01
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_state
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= StateTestComponent and
         cl.instance_methods.grep(/^assert_consistent$/).size > 0
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    
#    @world.run 1000 do
#      testers.each { |t| t.assert_consistent self }
#    end
  end
end

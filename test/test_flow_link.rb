#!/usr/bin/env ruby

require 'redshift/redshift'
require 'nr/random'

include RedShift

class FlowTestComponent < Component
  def finish test
  end
end

# test links in flows

class Flow_UsingLink < FlowTestComponent
  class Sub < Component
    flow { diff "x' = 2" }
  end
  
  link :sub => Sub
  setup { self.sub = create Sub }
  
  flow {
    diff "y' = sub.x"
    diff "t' = 1"
  }
  
  def assert_consistent test
    test.assert_equal_float(
      t**2,
      y,
      0.00000000001,
      "in #{state.name} after #{t} sec,\n")
  end
  
  def finish test
#    puts "y = #{y} at time #{t}"
  end
end

# test links in flows
# this was originally used to nail a bug in translate, maybe it's not needed

class Flow_UsingLink2 < FlowTestComponent
  class Sub < Component
    flow { alg "alg_dy = 2" }
    flow { diff "diff_dy' = 0" }; default { self.diff_dy  = 2 }
    continuous :const_dy; default { self.const_dy = 2 }
  end
  
  link :sub => Sub
  
  setup do
    self.sub = create Sub
  end
  
  flow do
    diff "t'  = 1"
    diff "y'  = 2"
    
    diff "y1' = sub.alg_dy"
    diff "y2' = sub.diff_dy"
    diff "y3' = sub.const_dy"
  end
  
  def assert_consistent test
    test.assert_equal_float(y, y1, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
    test.assert_equal_float(y, y2, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
    test.assert_equal_float(y, y3, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
  end
end

# test dynamic reconfiguration in flows

class Flow_Reconfig < FlowTestComponent
  class Sub < Component
    continuous :k; default { self.k = 2 }
    flow { alg "dy = k" }
  end
  
  link :sub => Sub
  
  setup do
    @sub1 = create Sub
    @sub2 = create Sub
    @sub2.k = - @sub1.k
    @next_t = 0
  end
  
  state :Sub1, :Sub2
  
  continuous :dy; setup { self.dy = 2 }
  
  flow Sub1, Sub2 do
    diff "y'  = sub.dy"
    diff "y1' = dy"
    diff "t'  = 1"
  end
  
  transition Enter => Sub1, Sub2 => Sub1 do
    guard { t >= @next_t }
    action { self.sub = @sub1; @next_t += 1; self.dy = sub.dy }
  end
  
  transition Sub1 => Sub2 do
    guard { t >= @next_t }
    action { self.sub = @sub2; @next_t += 1; self.dy = sub.dy }
  end
  
  def assert_consistent test
    test.assert_equal_float(y1, y, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
  end
end


#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestFlow < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.01; self.zeno_limit = 100 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_flow
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= FlowTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 1000 do
      testers.each { |t| t.assert_consistent self }
    end
    testers.each { |t| t.finish self }
  end
end

END {
  Dir.mkdir "tmp" rescue SystemCallError
  Dir.chdir "tmp"

  RUNIT::CUI::TestRunner.run(TestFlow.suite)

#  require 'plot/plot'
#  Plot.new ('gnuplot') {
#    add Flow_Reconfig::Y, 'title "y" with lines'
#    add Flow_Reconfig::Y1, 'title "y1" with lines'
#    add Flow_Reconfig::Y2, 'title "y2" with lines'
#    add Flow_Reconfig::Y3, 'title "y3" with lines'
#    show
#    pause 5
#  }

}

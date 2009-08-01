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
    test.assert_in_delta(
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
    test.assert_in_delta(y, y1, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
    test.assert_in_delta(y, y2, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
    test.assert_in_delta(y, y3, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
  end
end

# another test, maybe somewhat redundant, but what the hell
# in this case, we compare a system of equations in one component
# with the same system distributed among several

class Flow_UsingLink3 < FlowTestComponent
  class Sub1 < Component; end
  class Sub2 < Component; end

  class Sub1
    flow do
      diff "x'  = 3*y + sub2.f"
      diff "y'  = x + y*(0.1 * sub2.z - 0.2 * sub2.g)"
#     diff "z'  = (f + y + z) * 0.1"
#     alg  "f   = 0.3*(x + g) + 0.02"
#     alg  "g   = 2*z + h"
      alg  "h   = y - sub2.z + 1"
    end
    link :sub2 => Sub2
  end
  
  class Sub2
    flow do
#     diff "x'  = 3*y + f"
#     diff "y'  = x + y*(0.1 * z - 0.2 * g)"
      diff "z'  = (f + sub1.y + z) * 0.1"
      alg  "f   = 0.3*(sub1.x + g) + 0.02"
      alg  "g   = 2*z + sub1.h"
#     alg  "h   = y - z + 1"
    end
    link :sub1 => Sub1
  end
  
  link :sub1 => Sub1
  link :sub2 => Sub2
  
  setup do
    self.sub1 = create Sub1
    self.sub2 = create Sub2
    
    sub1.sub2 = sub2
    sub2.sub1 = sub1
  end
  
  flow do
    diff "x'  = 3*y + f"
    diff "y'  = x + y*(0.1 * z - 0.2 * g)"
    diff "z'  = (f + y + z) * 0.1"
    alg  "f   = 0.3*(x + g) + 0.02"
    alg  "g   = 2*z + h"
    alg  "h   = y - z + 1"
  end
  
  def assert_consistent test
    cmp = proc do |x, y| 
      test.assert_in_delta(x, y, 0.00000000001,
      "in #{state.name} after #{world.clock} sec,\n")
    end
    
    cmp[x,sub1.x]
    cmp[y,sub1.y]
    cmp[z,sub2.z]
    cmp[f,sub2.f]
    cmp[g,sub2.g]
    cmp[h,sub1.h]
  end
end

# test "lnk ? lnk.z : w" and "lnk1 = lnk2 ? x : y"

class Flow_Boolean < FlowTestComponent
  class Sub < Component
    flow {alg "x = 1"}
  end
  link :sub0 => Sub
  link :sub1 => Sub
  link :sub2 => Sub
  setup {
    self.sub1 = create Sub
    self.sub2 = sub1
  }
  flow {
    alg "y0 = sub1 ? sub1.x : 0"
    alg "y1 = sub0 ? 0 : sub2.x"
    alg "y2 = sub1 == sub2 ? sub1.x : 0"
  }
  def assert_consistent test
    cmp = proc do |x, y| 
      test.assert_in_delta(x, y, 0.00000000001,
      "in #{state.name} after #{world.clock} sec,\n")
    end
    
    cmp[1,y0]
    cmp[1,y1]
    cmp[1,y2]
  end
end

# test error handling of nil links

class Flow_NilLink < FlowTestComponent
  class Sub < Component
    continuous :z
  end
  link :nl => Sub
  continuous :x
  flow {alg "y = x ? nl.z : 0"}
  def assert_consistent test
    self.x = 1
    begin
      y
      test.assert_fail("Didn't detect nil link.")
    rescue Exception => e
## why does e seem to change class to CircularityError when asserting?
#      unless e.class == Flow::NilLinkError
#        test.assert_fail("Wrong kind of exception: #{e.class}")
#      end
#    puts e.class, e.message; exit
#      test.assert_kind_of(Flow::NilLinkError, e)
    end
#    test.assert_exception(Flow::NilLinkError) {y}
  end
end

# test self links

class Flow_SelfLink < FlowTestComponent
  link :sl => Flow_SelfLink
  setup {self.sl = self; self.y=1; self.z=1}
  flow {diff "y' = sl.y"; diff "z'=z"}
  def assert_consistent test
    test.assert_in_delta(z, y, 0.00000000001)
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
    test.assert_in_delta(y1, y, 0.00000000001,
      "in #{state.name} after #{t} sec,\n")
  end
end


#-----#

require 'test/unit'

class TestFlow < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step  = 0.01
    @world.zeno_limit = 100
  end
  
  def teardown
    @world = nil
  end
  
  def test_flow_link
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= FlowTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 100 do
      testers.each { |t| t.assert_consistent self }
    end
    testers.each { |t| t.finish self }
  end
end

END {

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

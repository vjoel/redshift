#!/usr/bin/env ruby

require 'redshift/redshift'
require 'nr/random'

include RedShift

class FlowTestComponent < Component
  def finish test
  end
end

# Empty flows are constant.

class Flow_Empty < FlowTestComponent
  continuous :x
  setup { self.x = 5 }
  def assert_consistent test
    test.assert_equal_float(5, x, 0.0000000000001)
  end
end

# Make sure timers work!

class Flow_Euler < FlowTestComponent
  flow { euler "t' = 1" }
  setup { self.t = 0 }
  def assert_consistent test
    test.assert_equal_float(world.clock, t, 0.0000000001)
  end
end

# Trig functions.

class Flow_Sin < FlowTestComponent
  flow { diff  "y' = y_prime", "y_prime' = -y" }
  setup { self.y = 0; self.y_prime = 1 }
  def assert_consistent test
    test.assert_equal_float(sin(world.clock), y, 0.000000001)
    ## is this epsilon ok? how does it compare with cshift?
  end
end

# Exp functions.

class Flow_Exp < FlowTestComponent
  flow { diff  "y' = y" }
  setup { self.y = 1 }
  def assert_consistent test
    test.assert_equal_float(exp(world.clock), y, 0.0001)
  end
end

# Polynomials.

class Flow_Poly < Flow_Euler    # note use of timer t from Flow_Euler
  flow {
    alg   "poly = -6 * pow(t,3) + 1.2 * pow(t,2) - t + 10"
    diff  "y' = y1", "y1' = y2", "y2' = y3", "y3' = 0"
  }
  setup { self.y = 10; self.y1 = -1; self.y2 = 1.2 * 2; self.y3 = -6 * 3 * 2 }
  def assert_consistent test
    test.assert_equal_float(poly, y, 0.000000001, "at time #{world.clock}")
  end
end

# Substitutability of algebraic flows (i.e. flows have function semantics)
# Dependencies of diff/euler/alg on alg, and alg on diff.

class Flow_Sub < FlowTestComponent
  s1 = "2*sin(u) + 1"
  s2 = "pow(u, 2) + 3 * u"
  
  f1 = proc { |v| s1.gsub(/u/,"(" + v + ")") }
  f2 = proc { |v| s2.gsub(/u/,"(" + v + ")") }
  
  flow {
    diff  "t'  = 1"
  
    alg   "x   = #{f1['t']}"
    alg   "xx  = #{f2['x']}"
    
    diff  "y0' = #{f2[f1['t']]}"
    diff  "y1' = #{f2['x']}"
    diff  "y2' = xx"
    
    euler "z0' = #{f2[f1['t']]}"
    euler "z1' = #{f2['x']}"
    euler "z2' = xx"
  }
  setup {
    self.t = 0
    self.y0 = self.y1 = self.y2 = self.z0 = self.z1 = self.z2 = 0
  }
  def assert_consistent test
    str = "at time #{t}"
    test.assert_equal_float(x, 2*sin(t) + 1, 0.000000001, str)
    test.assert_equal_float(xx, (2*sin(t) + 1)**2 + 3 * (2*sin(t) + 1),
      0.000000001, str)
    
    test.assert_equal_float(y0, y1, 0.000000001, str)
    test.assert_equal_float(y0, y2, 0.000000001, str)
    
    test.assert_equal_float(z0, z1, 0.000000001, str)
    test.assert_equal_float(z0, z2, 0.000000001, str)
  end
end

# state changes which change the type of flow

class Flow_StateChange < FlowTestComponent
  state :Alg, :Diff, :Euler, :Empty, :Switch
  
  flow Alg, Diff, Euler, Empty do
    diff "t' = 1"
  end
  
  flow Alg do
    alg "x = 10*t"
  end
  
  flow Diff do
    diff "x' = 10"
  end
  
  flow Euler do
    euler "x' = 10"
  end
  
  setup do
    self.x = 0
    @alarm_time = 0
    @alarm_seq = NR::Random::Exponential.new :mean => 0.5 #, :seed => 164184763
    @state_seq = NR::Random::Discrete.new :seed => nil, #916304301,
      :distrib =>
        {
          Alg   => 100,
          Diff  => 100,
          Euler => 100,
          Empty => 100
        }
    puts "\n\n  Flow_StateChange used the following seeds:"
    puts "  alarm seed = #{@alarm_seq.seed}"
    puts "  state seed = #{@state_seq.seed}"
  end
  
  transition Enter => Switch
  
  transition Alg   => Switch, Diff  => Switch,
             Euler => Switch, Empty => Switch do
    guard { t >= @alarm_time }
    action {
#      puts "Switching to #{@state_seq.next} at #{@alarm_time} sec."
#      puts "x = #{x}, t = #{t}."
      @alarm_time += @alarm_seq.next
#      puts "  Next switch at #{@alarm_time} sec.\n\n"
      ## unless we eval x here, the alg flow for x might not be up to date.
    }
  end
  
  transition Switch => Alg do
    guard { @state_seq.current == Alg }
  end
  transition Switch => Diff do
    guard { @state_seq.current == Diff }
  end
  transition Switch => Euler do
    guard { @state_seq.current == Euler }
  end
  transition Switch => Empty do
    guard { @state_seq.current == Empty }
  end
  
  transition Empty => Empty do
    guard { t > (@last_empty_t || 0) }
    action {
      @last_empty_t = t
      self.x = 10 * t   # manually update x
    }
  end
  
  def assert_consistent test
    # In the alg case, calling the accessor invokes the update method. We want
    # to test that alg flows work even if the update method isn't called.
    unless state == Alg
      test.assert_equal_float(
        10 * t,
        x,
        0.00000000001,
        "in #{state.name} after #{t} sec,\n")
    end
  end
  
  def finish test
#    puts "At finish: t = #{t}, alarm_time = #{@alarm_time}"
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

## TO DO ##
=begin
 
 flow A do
  alg "x = 3"
 end
 This should set x when trans A => B
 
 varying time step (dynamically?)
 
 handling of errors:
 
   circular dep.
   
   syntax
   
   assignment to alg var
   
=end

###class Flow_MixedType < FlowTestComponent
###  flow  {
###    euler "w' = 4"
###    diff  "x' = w"
###    diff  "y' = 4"
###    diff  "z' = y"  ### fails if these are more complex than just w or y
###  }
###  setup { self.w = self.y = 0; self.x = self.z = 0 }
###  def assert_consistent test
###    test.assert_equal_float(x, z, 0.001, "at time #{world.clock}")
###  end
###end


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

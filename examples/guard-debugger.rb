require 'redshift'

include RedShift

# This example is a simple debugger for stepping through guards.

# See examples/step-discrete-hook.rb for more examples of hook methods.

class DebuggingWorld < World
  def hook_eval_guard(comp, guard, enabled, trans, dest)
    puts "%-30p %-30p %-8s %6d" %
         [comp, guard, enabled ? "enabled" : nil, discrete_step]
    if enabled and dest != comp.state
      puts "Changing to state #{dest}"
    end
    puts "press <enter> to continue"
    gets
  end

  def hook_begin
    puts "-"*60
    puts "Begin discrete update in #{inspect}"
    puts "press <enter> to continue, ^C at any time to stop"
    puts "%-30s %-30s %-8s %6s" %
         %w(component guard status step)
    gets
  end

  def hook_end
    puts "End discrete update in #{inspect}"
    puts "press <enter> to continue"
    gets
  end
end

class Thing < Component
  state :A, :B
  start A
  
  continuous :x
  flow A do
    diff "x' = 1"
  end
  
  transition A => B do
    guard "x > 2"
  end
  
  transition B => A do
    guard "x < 1e-10"
    reset :x => 0
  end
  
  transition B => B do
    guard "x >= 1e-10"
    reset :x => "x-1"
  end
end

w = DebuggingWorld.new

w.create(Thing) do |th|
  th.name = 1
  th.x = 0.5
end

w.create(Thing) do |th|
  th.name = 2
  th.x = 5
  th.start Thing::B
end

w.age 100

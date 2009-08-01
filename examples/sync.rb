# Example of the sync construct: synchronizing transitions
# in two or more components.
#
# This is an example of unidirectional sync: component a takes
# its transition without requiring sync (it has a guard, but the
# guard only looks at the current state of the world, not at who
# else might emit some event), while b takes its transition
# _only_ if it can sync with a on the event e.
#
# See sync-queue.rb for a bi-directional example.

require 'redshift'

class A < RedShift::Component
  state :A1, :A2
  start A1
  
  flow A1 do
    diff " t' = 1 "
  end
  
  transition A1 => A2 do
    guard "t > 0.5"
    event :e
    action do
      puts "#{self} taking transition #{self.state} => #{self.dest}" +
           " at time #{world.clock}"
    end
  end
end

class B < RedShift::Component
  state :B1, :B2
  start B1
  
  link :a
  
  transition B1 => B2 do
    sync :a => :e # remove this line to see the difference
    action do
      puts "#{self} taking transition #{self.state} => #{self.dest}" +
           " at time #{world.clock}"
    end
  end
end

w = RedShift::World.new
b = w.create(B)
b.a = w.create(A)

w.evolve 1.0

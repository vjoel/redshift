# Shows how not all combinations of transitions are
# checked, because to do so would invite indeterminate
# behavior, and require exponential cpu.
#
# The first transition in c1 could sync with the second
# in c2, or the second in c2 with the first in c1. The
# problem is that neither of these pairs can be chosen in a
# natural way, so neither gets chosen.

require 'redshift'

class C < RedShift::Component
  link :other
  transition Enter => Exit do
    sync :other => :e
    event :f
  end
  transition Enter => Exit do
    sync :other => :f
    event :e
  end
end

w = RedShift::World.new
c1 = w.create C
c2 = w.create C
c1.other = c2
c2.other = c1

w.run 1
p c1
p c2

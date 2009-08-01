# Assigning to comp.dest can change the destination of
# the current transition.

require 'redshift'

class C < RedShift::Component
  state :S
  transition Enter => Exit do
    action do
      puts "changing dest from Exit to S"
      self.dest = S
    end
  end
  transition S => Exit do
    action do
      puts "S=>Exit"
    end
  end
end

w = RedShift::World.new
w.create C
w.run 1

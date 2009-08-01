require 'redshift'

class Sync < RedShift::Component
  link :next
  setup {self.next = nil} # or a comp that doesn't emit :no_such_event
  transition Enter => Exit do
    # this transition is checked first, but can't sync
    sync :next => :no_such_event
  end
  transition Enter => Exit do
    # so this trans is checked second
    action do
      puts "else (if no sync), take this transition"
    end
  end
end

w = RedShift::World.new
w.create(Sync)
w.run 1

# Shows how to use events to pass values among synced
# transitions. Note that event expressions are evaled
# *before* reset expressions are evaled, so that the
# the latter may reference the former.

require 'redshift'
include RedShift

class Emitter < Component
  transition Enter => Exit do
    event :e => 42.0
  end
end

class Receiver < Component
  link :c => Emitter
  constant :result
  transition Enter => Exit do
    sync :c => :e
    event :e => 0.42
    reset :result => "e + c.e"
  end
end

w = World.new
r = w.create(Receiver) {|r| r.c = r.create(Emitter)}
w.run 1
p r.result

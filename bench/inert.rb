require 'redshift'
require 'enumerator'

include RedShift

class Inert < Component
#  flow do
#    diff " t' = 1 "
#  end
end

class NonInert < Component
  n_states = 10
    # increasing this doesn't make the difference (w/ and w/o the inert
    # optimization) larger because the inerts go on strict sleep anyway.
  my_states = state((0...n_states).map {|i| "S#{i}"})
  start S0
  flow S0 do
    diff " t' = 1 "
  end
  transition S0 => S1 do
    guard " t >= 0.1 "
    reset :t => 0
  end
  my_states[1..-1].each_cons(2) do |s, t|
    transition s => t
  end
  transition my_states.last => my_states.first
end

n_inert     = 10000
n_non_inert = 0
n_steps     = 1000

w = World.new

n_non_inert.times {w.create(NonInert)}
n_inert.times {w.create(Inert)}

times = Process.times
t0 = Time.now
pt0 = times.utime #+ times.stime

w.run n_steps

puts "w.inert.size = #{w.inert.size}" if w.respond_to?(:inert)

times = Process.times
t1 = Time.now
pt1 = times.utime #+ times.stime
puts "process time: %8.2f" % (pt1-pt0)
puts "elapsed time: %8.2f" % (t1-t0)

__END__

The best case so far is:

without inert optimization
process time:     6.58
elapsed time:     6.59

with inert optimization
process time:     5.11
elapsed time:     5.12

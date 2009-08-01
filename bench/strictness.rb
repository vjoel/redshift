require 'my-profile'

$strict = ARGV.delete("-s")

# This makes a 5x difference!
if $strict
  $REDSHIFT_CLIB_NAME = "strictness-on"
else
  $REDSHIFT_CLIB_NAME = "strictness-off"
end

require 'redshift'
include RedShift

class SimpleComponent < Component

  if $strict
    strictly_continuous :y
  end
  continuous :x
  link :other => SimpleComponent

  state :A, :B; default { start A; self.other = self }
  
  flow A do
    diff "y' = 1 + x" # y still strict even though x is not
  end
  
  5.times do
    transition A => B do
      guard " pow(y, 2) - sin(y) + cos(y) < 0 "
    end
  end

end

class ComplexComponent < Component
  
  attr_accessor :start_value
  
  state :A, :B, :C, :D, :E1, :F; default { start A }
  
  flow A do
    diff "t' = 1"
  end
  
  transition A => B do
    guard "t > 1"
    action do
      if @start_value
        self.t = @start_value
        @start_value = nil
      else
        self.t = 0
      end
    end
  end
  
  transition B => C, C => D, D => E1, E1 => F, F => A
  
end

hz = 100
ts = 1.0/hz
w = World.new { |w| w.time_step = ts }
1000.times do w.create SimpleComponent end
hz.times do |i|
  cc = w.create ComplexComponent
  cc.start_value = i*ts
end

times = Process.times
t0 = Time.now
pt0 = times.utime #+ times.stime
profile false do
  w.run 1000
end
times = Process.times
t1 = Time.now
pt1 = times.utime #+ times.stime
puts "process time: %.2f" % (pt1-pt0)
puts "elapsed time: %.2f" % (t1-t0)

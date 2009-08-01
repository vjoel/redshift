require 'my-profile.rb'

$strict = (ARGV[0] =~ /^-s/)

if $strict
  $REDSHIFT_CLIB_NAME = "strictness-on"
else
  $REDSHIFT_CLIB_NAME = "strictness-off"
end

require 'redshift/redshift'
include RedShift

class SimpleComponent < Component

  if $strict
    strictly_continuous :t
  end

  state :A, :B; default { start A }
  
  flow A do
    diff "t' = 1"
  end
  
  5.times do
    transition A => B do
      guard " pow(t, 2) - sin(t) + cos(t) < 0 "
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

w = World.new { time_step 0.01 }
1000.times do w.create SimpleComponent end
100.times do |i|
  cc = w.create ComplexComponent
  cc.start_value = i/100
end

profile false do
  w.run 1000
end

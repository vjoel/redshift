#!/usr/bin/env ruby
require 'redshift'
require 'plot/plot'

include RedShift

class A < Component

  state :S0, :S1, :S2
  
  setup { start S0; @x = -100000; @t = 0 } # To override
  
  flow (S0, S1, S2) { diff "t' = 1" }
  
  flow (S0) { diff "x' = 1" }
  flow (S1) { diff "x' = -10" }   # To override
  flow (S2) { diff "x' = 100" }
  
  transition (S0 => S1) { guard { @t > 1 }; action { @t -= 1 } }

  # To override:
  transition (S1 => S2) {
    name :from_S1_to_S2
    guard { @t > 0.5 }; action { puts "KABOOM!" }
  }

end

class B < A

  state :S3
  
  setup { @x = 0 }

  flow (S1) { diff "x' = -20" }   # To override
  flow (S3) { diff "x' = 1000", "t' = 1" }
  
  transition (S1 => S2) {
    name :from_S1_to_S2
    guard { @t > 1 }; action { @t -= 1 }
  }
  
  transition (S2 => S3) { guard { @t > 1 }; action { @t -= 1 } }

end

class C < B

  state :S4

  flow (S1) { diff "x' = 10" }
  flow (S4) { diff "x' = 10000", "t' = 1" }

  transition (S3 => S4) { guard { @t > 1 }; action { @t -= 1 } }

end

class CC < Component

  state :S0, :S1, :S2, :S3, :S4

  setup { start S0; @x = 0; @t = 0 }

  flow (S0, S1, S2, S3, S4) { diff "t' = 1" }
  
  flow (S0) { diff "x' = 1" }
  flow (S1) { diff "x' = 10" }
  flow (S2) { diff "x' = 100" }
  flow (S3) { diff "x' = 1000" }
  flow (S4) { diff "x' = 10000" }
  
  transition (S0 => S1) { guard { @t > 1 }; action { @t -= 1 } }
  transition (S1 => S2) { guard { @t > 1 }; action { @t -= 1 } }
  transition (S2 => S3) { guard { @t > 1 }; action { @t -= 1 } }
  transition (S3 => S4) { guard { @t > 1 }; action { @t -= 1 } }
  
end

w = World.new { time_step 0.1 }

c = w.create(C)
cc = w.create(CC)

c_data = []
cc_data = []
state_data = []

while w.clock <= 5 do

  w.run
  c_data << [w.clock, c.x]
  cc_data << [w.clock, cc.x]
  state_data << [w.clock, c.state.name.to_s[-1..-1].to_i * 1000]
  if w.clock == 1.6
    puts c.state.name
    puts cc.state.name
  end
  
  if c.x != cc.x
    puts "Test failed--component defined by inheritance not equal to"
    puts "component defined without inheritance."
  end

end

Plot.new ('gnuplot') {
  add c_data, "title \"c\" w l"
  add cc_data, "title \"cc\" w l"
  add state_data, "w l"
  show
  pause 5
}

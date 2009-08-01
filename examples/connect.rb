require "redshift"
include RedShift

class A < Component
  continuous :x
  constant :k => 6.78
  flow do
    diff " x' = 2*x "
  end
end

class B < Component
  input :y
end

world = World.new

a = world.create(A)
b = world.create(B)

begin
  b.y
rescue RedShift::UnconnectedInputError => ex
  puts "As expected: #{ex}"
end

b.connect(:y, a, :x)
  # doesn't construct Port objects, so slightly more efficent
p(b.port(:y) << a.port(:x)) # Port#<< is alias for Port#connect

begin
  a.port(:x) << b.port(:y)
rescue TypeError => ex
  puts "As expected: #{ex}"
end

begin
  b.y = 1.23              # error
rescue NoMethodError => ex
  puts "As expected: #{ex}"
end

a.x = 4.56
p b.y                     # ok
p b

p b.port(:y).source == a.port(:x) # true
p b.port(:y).source_component     # a
p b.port(:y).source_variable      # :x

p a.port(:x).component    # a
p a.port(:x).variable     # :x

b.disconnect :y
b.port(:y).disconnect   # same
b.port(:y) << nil       # same

begin
  b.y
rescue RedShift::UnconnectedInputError => ex
  puts "As expected: #{ex}"
end

p A.offset_table
p B.offset_table

b.port(:y) << a.port(:x)
world.evolve 1 do
  p [a.x, b.y]
end

b.port(:y) << a.port(:k) # reconnect, but this time to a constant
world.evolve 0.5 do
  p [a.k, b.y]
end

puts <<END

  This example shows four things:
  
  1. you can connect an input to an input (b1 to b2, and b2 to b3).
  2. >> as an alternative to <<
  3. chaining >> (or <<)
  4. two input ports connected to the same var (b1 and b4 conn to a)
  
END

b1 = world.create(B)
b2 = world.create(B)
b3 = world.create(B)
b4 = world.create(B)

a.port(:x) >> b4.port(:y)
a.port(:x) >> b1.port(:y) >> b2.port(:y) >> b3.port(:y)

a.x = 3
p b3.y

puts <<END

  This example shows that connections are treated dynamically, not statically.
  Changing an upstream connection during a run affects all downstream vars.
  
END

a2 = world.create(A)
a2.x = 4
a2.port(:x) >> b1.port(:y)
p b2.y

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
b.port(:y) << a.port(:x) # Port#<< is alias for Port#connect, (returns RHS?)

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

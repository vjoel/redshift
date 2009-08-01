require 'redshift'

class Thing < RedShift::Component
  flow {
    diff "w' = 1"
    alg  "ww = 2*w + (sin(w) + cos(w))*(sin(w) + cos(w))"
    alg "www = ww-2"
    diff "u' = www"
  }
  def inspect data = nil
    d = "; #{data}" if data
    vars = [
      "w = #{w}"
    ]
    super "#{vars.join(", ")}#{d}"
  end
end

class Base < RedShift::Component
  flow {
    diff "x' = 1"
  }
  def inspect data = nil
    d = "; #{data}" if data
    vars = [
      "x = #{x}"
    ]
    super "#{vars.join(", ")}#{d}"
  end
end

class Tester < Base
  link :thing  => Thing
  flow {
    alg  "xx = 3*x"
    diff "y' = xx"
    diff "z' = y + 4*(thing.w+thing.u)"
  }

  def inspect data = nil
    d = "; #{data}" if data
    vars = [
      "xx = #{xx}",
      "y = #{y}",
      "z = #{z}"
    ]
    super "#{vars.join(", ")}#{d}"
  end
  
  setup do
    self.thing = create Thing
  end
end

#----------------------------------#

n_obj = 1000
n_iter = 100

# 10, 100_000 ==> 8.87 seconds

world = nil
$steps = [
  ["commit", proc { world = RedShift::World.new {|w| w.time_step = 0.05} }],
  ["create", proc { n_obj.times do world.create Tester end }],
  ["run",    proc { world.run n_iter }]
]

END {
#  puts "time_step = #{world.time_step}"
#  puts "clock = #{world.clock}"
#  t = world.find { |c| c.is_a? Tester }
#  p t
}

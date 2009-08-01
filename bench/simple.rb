require 'redshift/redshift'

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
  link :tester => Tester,
       :thing  => Thing
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

w = nil
$steps = [
  ["commit", proc { w = RedShift::World.new { time_step 0.05 } }],
  ["create", proc { 10000.times do w.create Tester end }],
  ["run",    proc { w.run 1000 }]
]

END {
  puts "time_step = #{w.time_step}"
  puts "clock = #{w.clock}"
  t = w.find { |c| c.is_a? Tester }
  p t
}

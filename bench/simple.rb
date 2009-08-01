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
      "x = #{x}",
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
  ["create", proc { 10.times do w.create Tester end }],
  ["run",    proc { w.run 10_000 }]
]

#END {
##  puts "time_step = #{w.time_step}"
#  t = w.find { |c| c.is_a? Tester }
#  p t
#}


__END__

  Possible advantages over SHIFT:
  
    * common subexpression optimization for links:
    
        x' = cos(foo.y) + sin(foo.y)
    
    * caching of algebraic equation results
    
        x  = ... # some complex formula
        y' = 2*x
        z' = 3*x
    
    * euler flows for timers that are not referred to in rk4 flows
    

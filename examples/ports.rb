# Shows how to use the port abstraction to refer to ports independently of the
# components (and classes) they are attached to.

require 'redshift'
include RedShift

class I < Component
  flow do
    diff " x' = -x "
  end
end

class A < Component
  flow do
    diff " t' = 1 "
    alg  " x  = cos(t) "
  end
end

class K < Component
  constant :x => 5.678
end

class W < Component
  input :x
  setup do
    port(:x) << create(I).port(:x)
  end
end

class L < Component
  link :i => I
  setup do
    self.i = create(I)
  end
  flow do
    alg " x = i.x "
  end
end

class Tester < Component
  input :x
end

w = World.new

comps = [I, A, K, W, L].map {|cl| w.create(cl)}
ports = comps.map {|comp| comp.port(:x)}
values = ports.map {|port| port.value}

p values # ==> [0.0, 1.0, 5.678, 0.0, 0.0]

tester = w.create(Tester)
values = ports.map do |port|
  tester.port(:x) << port
  tester.x
end

p values # same as above


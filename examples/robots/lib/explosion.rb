class Explosion < RobotComponent
  continuous :size, :max_size, :x, :y, :vx, :vy
  continuous :t, :prev_t
  
  setup do
    self.t = self.prev_t = 0
  end
  
  state :Expanding
  start Expanding
   
  flow Expanding do
    diff " x' = vx "
    diff " y' = vy "
    diff " size' = 10 * sqrt(size) "
    diff " t' = 1 "
  end
  
  transition Expanding => Done do
    guard " size > max_size "
  end
  
  transition Expanding => Expanding do
    guard " t > prev_t "
    action do
      world.grep(Robot) do |r|
        if (x - r.x)**2 + (y - r.y)**2 < size**2
          r.messages <<
            Robot::InflictDamage.new(10*(max_size - size)*(t - prev_t))
        end
      end
    end
    reset :prev_t => "t"
  end
  
  def tk_add
    "add explosion #{id} - 0 #{x} #{y} 0 #{size} #{-size}"
  end
  
  # emit string representing current state
  def tk_update
    fade = ("%x" % ((size / max_size) * 256)) * 2
    "moveto #{id} #{x} #{y}\n" +
    "param #{id} 0 #{size}\n" +
    "param #{id} 1 #{-size}\n" +
    "param #{id} 2 0xFF#{fade}"
  end
end

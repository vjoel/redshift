class Robot < RobotComponent
  require 'radar'
  require 'explosion'
  require 'missile'

  continuous :x, :y, :vx, :vy, :v, :heading, :power, :health
  link :radar => :Radar
  
  InflictDamage = Struct.new(:value)
  queue :messages
  
  default do
    self.radar = create Radar
    radar.host_robot = self
    
    self.power = 100
    self.health = 100
  end
  
  state :Stopped, :Rolling, :Exploding
  start :Rolling
  
  flow Stopped, Rolling do
    alg " vx = v * cos(heading) "
    alg " vy = v * sin(heading) "

    alg " heading_deg = fmod(heading * #{180/Math::PI}, 360)"

    diff " x' = vx "
    diff " y' = vy "
    
    # a bit of friction, i.e. deceleration proportional to velocity
    diff " v' = -0.01 * v"
  end
  
  flow Rolling do
    # it takes power to maintain speed
    diff " power' = -1 "
  end
  
  transition Rolling => Stopped do
    guard " power <= 0 "
  end
  
  transition Rolling => Exploding, Stopped => Exploding do
    guard " health <= 0 "
    action do
      create Explosion do |e|
        e.size = 1
        e.max_size = 60
        e.x = x
        e.y = y
        e.vx = vx
        e.vy = vy
      end
    end
  end
  
  transition Exploding => Done
  
  transition Rolling => Rolling, Stopped => Stopped do
    wait :messages => InflictDamage
    action do
      m = messages.pop
      case m
      when RedShift::SimultaneousQueueEntries
        dmg_msgs, other = m.partition {|n| InflictDamage === n}
        messages.unpop other
        dmg_msgs.each do |n|
          self.health -= n.value
        end
      else
        self.health -= m.value
      end
    end
  end

  # return string that adds an instance of the shape with label t.name,
  # position based on (x, y), and rotation based on heading
  def tk_add
    "add robot #{id} - 10 #{x} #{y} #{heading}\n" +
    "param #{id} 0 #{name}\n" +
    "param #{id} 1 359\n" +
    "param #{id} 2 359"
  end
  
  # emit string representing current state
  def tk_update
    e = (power / 100.0) * 359.9
    h = (health / 100.0) * 359.9
    "moveto #{id} #{x} #{y}\n" +
    "rot #{id} #{heading}\n" +
    "param #{id} 1 #{e}\n" +
    "param #{id} 2 #{h}"
  end
  
  def show_status
    printf \
      "%5.3f sec: closest blip is %s, at %8.3f meters, bearing %3d degrees\n",
      world.clock,
      radar.nearest_robot ? radar.nearest_robot.name : "none",
      radar.distance,
      (radar.angle * 180/Math::PI).round.abs
  end
end

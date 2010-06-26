class Missile < RobotComponent
  require 'explosion'
  
  link :target => Robot
  
  continuous :x, :y, :vx, :vy, :v, :heading, :power
  constant :turn_rate
  
  state :Seeking
  start Seeking
  
  default do
    self.power = 40
    self.v = 20
    self.turn_rate = 60 * Math::PI / 180 # convert from degrees per sec
  end

  flow Seeking do
    alg " vx = v * cos(heading) "
    alg " vy = v * sin(heading) "

    diff " x' = vx "
    diff " y' = vy "
    
    diff "power' = -1"
    
    alg " distance =
        sqrt(
          pow(x - target.x, 2) +
          pow(y - target.y, 2) ) "
    
    alg " angle =
        atan2(target.y - y,
              target.x - x) "
    
    alg " error = fmod(heading - angle, 2*#{Math::PI}) "
    diff " heading' = turn_rate * (
            error < #{-Math::PI/2} ?
              #{-Math::PI/2} :
              (error > #{Math::PI/2} ?
                #{Math::PI/2} : -error)) "
  end

  transition Seeking => Done do
    guard "power < 0"
  end
  
  transition Seeking => Done do
    guard "distance < 1"
    action do
      unless target.state == Exit
        create Explosion do |e|
          e.size = 1
          e.max_size = power
          e.x = x
          e.y = y
          e.vx = vx
          e.vy = vy
        end
      end
    end
  end

  # return string that adds an instance of the shape with label t.name,
  # position based on (x, y), and rotation based on heading
  def tk_add
    "add missile #{id} - 11 #{x} #{y} #{heading}"
  end
  
  # emit string representing current state
  def tk_update
    "moveto #{id} #{x} #{y}\n" +
    "rot #{id} #{heading}"
  end
end

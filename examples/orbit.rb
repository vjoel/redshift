# A very simple simulation of orbital mechanics. Planets orbit sun, but do
# not interact with each other.

require 'redshift'
require 'redshift/util/tkar-driver'

include RedShift

module OrbitWorld
  def next_id
    @next_id ||= 1
    @next_id += 1
  end
  
  def tkar
    @tkar ||= TkarDriver.new do |pipe|
      pipe.puts <<-END
        title Orbit example
        background black
        height 600
        width 600
        view_at -50 -50
        zoom_to 4

        shape planet oval*0,*0,*1,*1,oc:*2,fc:*2 \
          text0,3,anchor:c,justify:center,width:100,text:*3,fc:white
      END
      ## the view_at seems to be needed to overcome a little
      ## centering bug in tkar
      
      # Add the Sun, but never move it.
      pipe.puts "add planet 0 - 5 0 0 0"
      pipe.puts "param 0 0 4"
      pipe.puts "param 0 1 -10"
      pipe.puts "param 0 2 yellow"
      pipe.puts "param 0 3 ."

      grep(Planet) do |pl|
        pipe.puts pl.tk_add
        pipe.puts pl.tk_update
      end
    end
  end
  
  def tk_update
    tkar.update do |pipe|
      grep(Planet) do |pl|
        pipe.puts pl.tk_update
      end
    end
  end
end

class Planet < Component
  attr_accessor :name, :id, :color
  constant :size, :mass
  
  constant :g => 1.0
  constant :mass_sun => 1000.0
  
  default do
    @id = world.next_id
    @name = id
    @color = "white"
    self.mass = 1
    self.size = 1
  end
  
  flow do
    diff " x'  = vx "
    diff " y'  = vy "
    
    diff " vx' = ax "
    diff " vy' = ay "
    
    alg  " r = hypot(x, y) "
    alg  " w = -g * (mass_sun + mass) / pow(r, 3) "
    alg  " ax = w * x "
    alg  " ay = w * y "
  end

  # return string that adds an instance of the shape with label t.name,
  # position based on (x, y), and
  # rotation based on (x', y')
  def tk_add
    "add planet #{id} - 10 #{x} #{y} 0\n" +
    "param #{id} 0 #{size}\n" +
    "param #{id} 1 #{-size}\n" +
    "param #{id} 2 #{color}\n" +
    "param #{id} 3 #{name}"
  end
  
  # emit string representing current state
  def tk_update
    "moveto #{id} #{x} #{y}"
  end
end

w = World.new
w.extend OrbitWorld

w.time_step = 0.1

earth = w.create Planet do |pl|
  pl.name = "Earth"
  pl.color = "blue"
  pl.size = 2
  pl.mass = 100
  pl.x = 40
  pl.y = 0
  pl.vx = 0
  pl.vy = 5
end

ellipto = w.create Planet do |pl|
  pl.name = "Ellipto"
  pl.color = "bisque2"
  pl.size = 2
  pl.mass = 100
  pl.x = 80
  pl.y = 0
  pl.vx = 0
  pl.vy = 2
end

w.evolve 1000 do
  #p [earth.x, earth.y]
  w.tk_update
  #sleep 0.01
end

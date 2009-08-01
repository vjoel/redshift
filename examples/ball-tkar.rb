# Example showing how to use tkar to animate a redshift simulation.
#
# Tkar can be found at http://path.berkeley.edu/~vjoel/vis/tkar

require 'redshift'
include RedShift

class Ball < Component
  continuous :x, :y, :v
  
  flow do
    diff "y' = v"
    diff "v' = -9.8"
  end
  
  transition do
    guard "y - 5 < 0 && v < 0"
    reset :v => "-v"
  end
  
  attr_accessor :id # so we can keep track of which is which in animation
end

world = World.new
#world.time_step = 0.01

ball_count = 10
balls = Array.new(ball_count) do |id|
  world.create(Ball) do |ball|
    ball.x = id * 10
    ball.y = rand(450) + 100
    ball.v = 0
    ball.id = id
  end
end

begin
  ## need --quiet option?
  IO.popen("tkar --flip -v", "w") do |tkar|
    # --flip means positive y is up
    tkar.puts %{
      title Bouncing ball
      background gray95
      height 600
      width 600
      bounds -300 0 300 600
      shape ball oval-5,-5,5,5,fc:darkgreen,oc:red
      shape ground line*0,0,*1,0,fc:purple,wi:4
      add ground 10000 - 10 0 0 0 -300 300
      view_at 0 540
    }
    balls.each do |ball|
      tkar.puts %{
        add ball #{ball.id} - 100 #{ball.x} #{ball.y} 0
      }
    end
    tkar.flush
    world.evolve 1000 do
      balls.each do |ball|
        tkar.puts "move #{ball.id} #{ball.x} #{ball.y}"
      end
      tkar.puts "update"
      tkar.flush
      #sleep 0.01
      ## need timer to make this realistic
    end
    puts "Press <enter> when done"
    gets
  end
rescue Errno::EPIPE, Interrupt
  puts "Exited."
end

#!/usr/bin/env ruby
require 'redshift/redshift'
require 'plot/plot'
require 'nr/random'

include RedShift
include NR::Random
include Math


class Ball < Component

  flow {
    euler " x' = @vx "
    euler " y' = @vy "
  }
  
  defaults {
    @x = 0
    @y = 0
  }
  
end

world = World.open "ball.world"

unless world

  world = World.new {time_step 0.01}

  seq = UniformSequence.new :min => 0, :max => 2*PI

  5.times do
    world.create(Ball) {
      angle = seq.next
      @vx = cos angle
      @vy = sin angle
    }
  end
  
end

balls = world.select { |c| c.type == Ball }

data = {}
for b in balls
  data[b] = [[b.x, b.y]]
end

50.times do
  world.run
  for b in balls
    data[b] << [b.x, b.y]
  end
end

Plot.new ('gnuplot') {

  command 'set xrange [ -2 : 2 ]; set yrange [ -2 : 2 ]'
  
  for b in balls
    add data[b], "title \"#{balls.index(b)}\" with lines"
  end
  
  show
  pause 5
}

world.save "ball.world"

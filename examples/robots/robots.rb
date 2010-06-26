$LOAD_PATH.unshift 'lib'
require 'base'

world = RobotWorld.new
world.time_step = 0.01

r1 = world.create Robot do |r|
  r.name = "robot 1"
  r.x = 0
  r.y = 0
end

r2 = world.create Robot do |r|
  r.name = "robot 2"
  r.x = -50
  r.y = 0
  r.heading = 0.1 * Math::PI
  r.v = 10
end

r3 = world.create Robot do |r|
  r.name = "robot 3"
  r.x = 70
  r.y = 10
  r.heading = -0.9 * Math::PI
  r.v = 5
end

30.times do |i|
  world.create Missile do |m|
    m.x = -40
    m.y = 40 + i*2
    m.v = 20 - (i%10)
    m.target = r2
  end
end

20.times do |i|
  world.create Missile do |m|
    m.x = -30
    m.y = 40 + i*2
    m.v = 20 - (i%10)
    m.heading = i / 20
    m.target = r3
  end
end

robots = world.grep(Robot)
robots.each do |r|
  r.radar.track_robots robots - [r]
end

world.main_loop_with_shell_and_tk(ARGV)

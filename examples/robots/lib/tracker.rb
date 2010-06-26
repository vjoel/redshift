# computes true distance and bearing angle to a single target,
# but won't scale up very well
class Tracker < RobotComponent
  link :host => Robot
  link :target => Robot
  
  flow do
    alg " distance =
        sqrt(
          pow(host.x - target.x, 2) +
          pow(host.y - target.y, 2) ) "
    alg " angle =
        atan2(target.y - host.y,
              target.x - host.x) "
  end
end

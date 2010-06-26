require 'tracker'

class Radar < RobotComponent
  constant :period => 0.200
  continuous :t
  continuous :distance
  continuous :angle
  attr_accessor :host_robot, :nearest_robot
  link :nearest_tracker => Tracker
  
  attr_accessor :trackers
  default do
    self.trackers = []
  end
  
  # add +robots+ to the list of objects tracked by this radar
  def track_robots *robots
    robots.flatten.each do |robot|
      tracker = create Tracker
      tracker.host = host_robot
      tracker.target = robot
      trackers << tracker
    end
  end
  
  state :Sleep, :Measure
  start Sleep
  
  flow Sleep do
    diff " t' = -1 "
  end

  flow Sleep, Measure do
    alg " angle_deg = fmod(angle * #{180/Math::PI}, 360)"
  end
  
  transition Sleep => Measure do
    guard " t <= 0 "
    action do
      scan_for_nearest_robot
    end
  end
  
  transition Measure => Sleep do
    reset :t => "period"
  end

  def scan_for_nearest_robot
    self.nearest_tracker = trackers.min_by {|tracker| tracker.distance}
    if nearest_tracker
      self.nearest_robot = nearest_tracker.target ## how to delay this?
      self.distance = nearest_tracker.distance
      self.angle = nearest_tracker.angle
    end
  end
end

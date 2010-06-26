# This file encapsulates some relatively uninteresting tweaks and additions
# to make the demo go smoothly.

require 'redshift'

class RobotComponent < RedShift::Component
  attr_accessor :name # for display; can be anything
  attr_reader   :id   # for keeping track of tk objects; must be uniq int
  
  default do
    @id = world.next_id
    @name = id
  end

  def tk_delete
    "delete #{id}"
  end
  
  state :Done
  
  transition Done => Exit do
    action do
      world.exited << self
    end
  end
end

require 'shell-world'
require 'robot'

class RobotWorld < RedShift::World
  include ShellWorld

  def show_status
    grep(Robot) {|r| r.show_status}
    nil
  end
end

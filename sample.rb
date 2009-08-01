require 'redshift.rb'

include RedShift

w1 = World.new
w2 = World.new


class Ball < Component

	input [:radius, 10]
	

end # class Ball

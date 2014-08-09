= Robots

An example covering some of the basic language features plus some techniques for interactive simulation and for animating simulation output.

To run the example:

    ruby robots.rb

Press ^C to break into a command shell, and then ^D to continue the simulation run. The "help" command in the shell shows you the commands beyond the basic irb.

Use -h from the command line to see the switches.

To change the setup of the world, edit robots.rb. You can add and move robots and missles.

You can also move the objects interactively in the Tk visualization.

Currently, the robots move around and the missles track and hit them.

= To do

== robots physics

- collision detection and effect on robot health

- walls and obstacles

== robot control

- command language to evade attackers and launch missiles based on radar

- maybe similar to RoboTalk (from RoboWar)

- multirobot coordination using comm channels

== game mechanics

- robot shop

- tournaments

== dev tools

- debugger

- plotter

== visualization

- for each sensor, show nearest robot by drawing arrow

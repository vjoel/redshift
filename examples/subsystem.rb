# Shows how to use subsystems in redshift like in simulink.

require 'redshift'
include RedShift

# First, let's define some "blocks" to put inside the subsystem.

# A generic integrator block.
class Integrator < Component
  input :dx_dt
  flow { diff " x' = dx_dt " }
end

# A specific algebraic equation.
class Alg < Component
  input :in
  flow { alg " out = pow(in, 2) - 6 * in - 10 " }
end

# Now, the subsystem container:
class Subsystem < Component
  input :in
  input :out  # declared as input because it is input from subcomponent
end

# We need a data source, so let's just use a linear input:
class Timer < Component
  flow { diff " time' = 1 " }
end

# A component to check results by solving analytically:
class Checker < Component
  input :in
  constant :c # for integration constant
  flow { alg " true_result = pow(in, 3)/3 - 3 * pow(in, 2) - 10 * in + c " }
    # symbolically integrated
end

# In practice, the subsystem, with the sub-blocks and connections created below,
# could be coded in much simpler way in redshift, by combining the differential
# and algebraic equations and even the timer. Sometimes, however, input ports
# are a convenient way to reuse functionality. They have the advantage over link
# variables of not needing to know the class of the source component, so it's
# possible to have independent libraries of them.
class MuchSimpler < Component
  flow {
    diff " t' = 1 "
    diff " x' = pow(t, 2) - 6 * t - 10 "
  }
end

# Enough definitions. Now, before we can run anything, we need to construct
# instances of these classes in a world.
world = World.new

# Create the subsystem and its sub-blocks.
subsystem = world.create Subsystem do |sys|
  # create the sub-blocks (note that the vars are local, so the 
  # sub-blocks are encapsulated at the syntactic level):
  int = world.create(Integrator)
  alg = world.create(Alg)
  
  # specify an initial condition
  int.x = 200
  
  # wire everything together
  sys.port(:in) >> alg.port(:in)
  alg.port(:out) >> int.port(:dx_dt)
  int.port(:x) >> sys.port(:out)
end

# Create the data source and connect to the subsystem:
timer = world.create(Timer)
timer.time = 0
timer.port(:time) >> subsystem.port(:in)

# Create the checker and connect to timer:
checker = world.create(Checker)
checker.port(:in) << timer.port(:time)
checker.c = subsystem.out # must agree on initial condition

# Compare with a single-component implementation.
much_simpler = world.create(MuchSimpler)
much_simpler.x = subsystem.out # must agree in initial condition

result = []; error = []; error2 = []
gather = proc do
  result << [timer.time, subsystem.out]
  error  << [timer.time, subsystem.out - checker.true_result]
  error2 << [timer.time, subsystem.out - much_simpler.x]
end

gather.call
world.evolve 20 do
  gather.call
end

require 'redshift/util/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Subsystem"}
  plot.command %{set xlabel "time"}
  plot.add result, %{title "subsystem f(t)" with lines}
  plot.add error, %{title "error in f(t)" with lines}
  plot.add error2, %{title "error2 in f(t)" with lines}
end

sleep 1 if /mswin32|mingw32/ =~ RUBY_PLATFORM

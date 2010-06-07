# Records values of variables over time.
#
# A Tracer manages a two-tier system typical of simulations: Object and
# Variable. The Object tier is really a hash on arbitrary keys. The keys can be
# simulation objects, or they can be strings, symbols, etc.
#
# The values of this hash are the the Variable tier. More precisely, each value
# is another hash mapping variable name to Tracer::Var instances.
#
# The Tracer::Var class provides the primary per-variable functionality, and it
# can be used without the Tracer class. For example, it could be attched
# directly to the simulation object itself.
#
# The two-tier structure permits add/remove operations at the Object tier, which
# is convenient when objects enter or leave a simulation. Keeping the Tracer
# tiers separate from simulation objects makes it easier to run those objects
# without tracing, or to change the tracing strategy.
#
class Tracer
  require 'redshift/util/tracer/var'

  attr_reader :var_map, :default_opts

  # Construct a Tracer which passes the +default_opts+ on to each
  # var, overridden by the opts passed to #add.
  def initialize default_opts = {}
    @var_map = {}
    @default_opts = default_opts
  end

  # Adds an item to the list of things to be recorded during #run!.
  #
  # If no block is given, the +key+ must be an object which has an
  # attribute +name+.
  #
  # If a block is given, then it is called during #run! to determine
  # the value that is stored in the Tracer. The +key+ and +name+ can be
  # anything and are significant only for looking up traces in the Tracer.
  # If the block accepts an argument, the associated +Var+ object is passed.
  #
  def add key, name, opts={}, &block
    @var_map[key] ||= {}
    var = Var.new(key, name, default_opts.merge(opts), &block)
    @var_map[key][name] = var
  end

  # If +name+ is given, remove the trace of that variable
  # associated with +key+. If name is not given, remove all traces
  # associated with +key+. The removed Tracer::Var or hash of such objects
  # is returned.
  def remove key, name = nil
    if name
      h = @var_map[key]
      r = h.delete name
      @var_map.delete key if h.empty?
      r
    else
      @var_map.delete key
    end
  end

  # Called during a sumulation to record traces. In RedShift, typically called
  # in the evolve {..} block, or in action clauses of transitions, or in
  # hook methods.
  def run!
    @var_map.each do |key, h|
      h.each do |name, var|
        var.run!
      end
    end
  end

  # Convenience method to get a Var or a hash of Vars. Returns +nil+ if not
  # found.
  def [](key, name = nil)
    if name
      h = @var_map[key]
      h && h[name]
    else
      @var_map[key]
    end
  end

  class MissingVariableError < StandardError; end
  class MissingKeyError < StandardError; end

  # Yield once for each var associated with the +key+, or just once if
  # +name+ given.
  def each_var(key, name = nil)
    if name
      var = self[key, name] or
        raise MissingVariableError, "No such var, #{key}.#{name}"
      yield var
    else
      h = @var_map[key] or
        raise MissingKeyError, "No such key, #{key}"
      h.each do |name, var|
        yield var
      end
    end
  end

  # Make a variable (or all vars of a key) inactive. No data will be traced
  # unti #start is called.
  def stop(key, name = nil)
    each_var(key, name) {|var| var.active = false}
  end

  # Make a variable (or all vars of a key) active.
  def start(key, name = nil)
    each_var(key, name) {|var| var.active = true}
  end
end

require 'pp'

#
# Note: This is not a complete program specification, since Procs and methods
# cannot be dumped. It is useful for inspecting the vars, flows, and also
# transitions, to the extent that these are defined without Procs.
#

class World
  def World.new(*args)
    exit ## could just call the code below and then exit...
  end
end

END {
  ## this duplicates some code from Library
  cc = []
  ObjectSpace.each_object(Class) do |cl|
    cc << cl if cl < Component # Component is abstract
  end
  cc = cc.sort_by {|c| c.ancestors.reverse!.map!{|d|d.to_s}}

  cc.each do |c|
    puts "=" * 60
    puts "=" * 20 + "class #{c.name}"
    c.instance_eval do
      instance_variables.each do |var|
        val = eval(var)
        puts "#{var}:"
        pp val
      end
    end
  end
}

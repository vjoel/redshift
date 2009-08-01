require 'cgen/cshadow'

module RedShift

unless defined? CLibName
  CLibName =
    if $0 == "\000PWD"  # irb 1.6.5 bug
      "irb"
    else
      $0.dup    ## use something better than $0?
    end
  CLibName.sub!(/\.rb/, "")
  CLibName.sub!(/\A\.\//, "")
  CLibName.sub!(/-/, "_") ## What to do about other symbols?
  CLibName << '_clib'
  ### must also deal with 'examples/sample.rb'
end

CLib = CGenerator::Library.new CLibName
CLib.include '<math.h>'

class Component
###  include CShadow
# should avoid creating when no need to
# problem when 'ruby foo/bar.rb': cgen.rb:623: "foo/bar" not valid name.
###  shadow_library CLib
end

class World
###  include CShadow
###  shadow_library CLib
end

end # module RedShift

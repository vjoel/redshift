require 'cgen/cshadow'

module RedShift

unless defined? CLibName
  CLibName =
    if $0 == "\000PWD"  # irb in ruby 1.6.5 bug
      "irb"
    else
      File.basename($0)
    end
  CLibName.sub!(/\.rb$/, "")
  CLibName.sub!(/-/, "_")
    # other symbols will be caught in CGenerate::Library#initialize.
  CLibName << '_clib'
end

CLib = CGenerator::Library.new CLibName
CLib.include '<math.h>'

class Component
  include CShadow
  shadow_library CLib
end

class World
  include CShadow
  shadow_library CLib
end

end # module RedShift

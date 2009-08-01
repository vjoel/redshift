#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

class LinkTestComponent < Component
  class Foo < Component; end
  link :foo => Foo
end

class Link_1 < LinkTestComponent
  setup {self.foo = Foo.new}
end

class Link_2 < LinkTestComponent
  class Bar < Foo; end
###  link :foo => Bar ### ==> "already exists"
end

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestInheritLink < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_link
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= LinkTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 100
    testers.each { |t| t.assert_consistent self }
  end
end

END {
  Dir.mkdir "tmp" rescue SystemCallError
  Dir.chdir "tmp"

  RUNIT::CUI::TestRunner.run(TestInheritLink.suite)
}

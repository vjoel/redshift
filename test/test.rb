#!/usr/bin/env ruby

if RUBY_VERSION == "1.6.6"
  puts "DEBUG mode is turned off in Ruby 1.6.6 due to bug."
  $DEBUG = false
else
  $DEBUG = true
end

if RUBY_VERSION == "1.8.0"
  class Module
    alias instance_methods_with_warning instance_methods
    def instance_methods(include_super=true)
      instance_methods_with_warning(include_super)
    end
  end
end

$REDSHIFT_DEBUG=3 ## what should this be?

### have to fix the CLIB_NAME problem before can do this
### require 'redshift' ## all the tests will need this anyway

if ARGV.delete("-j2") ## parse better
  jobs = 2
else
  jobs = 1
end

pat = ARGV.join("|")
tests = Dir["test_*.rb"].grep(/#{pat}/)
tests.sort!

#trap("CLD") do
#  # trapping "INT" doesn't work because child gets the signal
#  exit!
#end

require 'rbconfig'
ruby = Config::CONFIG["RUBY_INSTALL_NAME"]

pending = tests.dup
failed = []

workers = (0...jobs).map do |i|
  Thread.new do
    loop do
      file = pending.shift
      break unless file
      puts "_"*50 + "\nStarting #{file}...\n"
      if not system "#{ruby} #{file}" ## problem with interleaved outputs
        ## should use popen3 so we can weed out successful output
        failed << file
      end
    end
  end
end

workers.each {|w| w.join}

puts "_"*50
if failed.empty?
  puts "All tests passed."
else
  puts "Some tests failed:", failed
end

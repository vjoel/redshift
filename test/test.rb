#!/usr/bin/env ruby

if RUBY_VERSION == "1.6.6"
  puts "DEBUG mode is turned off in Ruby 1.6.6 due to bug."
  $DEBUG = false
else
###  $DEBUG = true
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
### require 'redshift/redshift' ## all the tests will need this anyway

tests = ARGV.empty? ? Dir["test_*.rb"] : ARGV
tests.sort!
tests.delete_if {|f| /\.rb\z/ !~ f}

tests.each do |file|
  puts "_"*50 + "\nStarting #{file}...\n"
  system "ruby #{file}" ### better way?
#  pid = fork { ## should use popen3 so we can weed out successful output
#    $REDSHIFT_CLIB_NAME = file
#    require 'redshift/redshift'
#    load file
#  }
#  Process.waitpid(pid)
  ### should trap SIGINT and kill child process
end

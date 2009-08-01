#!/usr/bin/env ruby

if RUBY_VERSION == "1.6.6"
  puts "DEBUG mode is turned off in Ruby 1.6.6 due to bug."
  $DEBUG = false
else
###  $DEBUG = true
end

$REDSHIFT_DEBUG=true

tests = ARGV.empty? ? Dir["test_*.rb"] : ARGV
tests.sort!
tests.delete_if {|f| /\.rb\z/ !~ f}

tests.each do |file|
  puts "_"*50 + "\nStarting #{file}...\n"
  pid = fork {
    $REDSHIFT_CLIB_NAME = file
    require 'redshift/redshift'
    load file
  }
  Process.waitpid(pid)
  ### should trap SIGINT and kill child process
end

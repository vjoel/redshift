# A slim command-line parser that does one thing well: turn an array of
# strings, such as ARGV, into a hash of recognized options and their
# arguments, leaving unrecognized strings in the original array.
#
# Argos was Odysseus' faithful dog, who was good at recognizing ;)
#
# Synopsis:
#
#    require 'argos'
#
#    optdef = {
#      "v"   => true,
#      "n"   => proc {|arg| Integer(arg)}
#    }
#
#    argv = %w{-v -n10 filename}
#    opts = Argos.parse_options(argv, optdef)
#    p opts    # ==> {"v"=>true, "n"=>10}
#    p argv    # ==> ["filename"]
#
# Features:
#
# - Operates on ARGV or any given array of strings.
#
# - Output is a hash of {option => value, ...}.
#
# - You can merge this hash on top of a hash of defaults if you want.
#
# - Supports both long ("--foo") and short ("-f") options.
#
# - A long option with an argument is --foo=bar or --foo bar.
#
# - A short option with an argument is -fbar or -f bar.
#
# - The options -x and --x are synonymous.
#
# - Short options with no args can be combined as -xyz in place of -x -y -z.
#
# - If -z takes an argument, then -xyz foo is same as -x -y -z foo.
#
# - The string "--" terminates option parsing, leaving the rest untouched.
#
# - The string "-" is not considered an option.
#
# - ARGV (or other given array) is modified: it has all parsed options
#   and arguments removed, so you can use ARGF to treat the rest as input files.
#
# - Unrecognized arguments are left in the argument array. You can catch them
#   with grep(/^-./), in case you want to pass them on to another program or
#   warn the user.
#
# - Argument validation and conversion are in terms of an option definition
#   hash, which specifies which options are allowed, the number of arguments
#   for each (0 or 1), and how to generate the value from the argument, if any.
#
# - Repetition of args ("-v -v", or "-vv") can be handled by closures. See
#   the example below.
#
# - Everything is ducky. For example, handlers only need an #arity method
#   and a #[] method to be recognized as callable. Otherwise they are treated
#   as static objects.
#
# Limitations:
#
# - A particular option takes either 0 args or 1 arg. There are no optional
#   arguments, in the sense of both "-x" and "-x3" being accepted.
#
# - Options lose their ordering in the output hash (but they are parsed in
#   order and you can keep track using state in the handler closures).
#
# - There is no usage/help output.
#
# Copyright (C) 2006-2009 Joel VanderWerf, mailto:vjoel@users.sourceforge.net.
#
# License is the Ruby license. See http://www.ruby-lang.org.
#
module Argos
  module_function

  # Raised (a) when an option that takes an argument occurs at the end of the
  # argv list, with no argument following it, or (b) when a handler barfs.
  class OptionError < ArgumentError; end
  
  # Called when an option that takes an argument occurs at the end of the
  # argv list, with no argument following it.
  def argument_missing opt
    raise OptionError, "#{opt}: no argument provided."
  end
  
  def handle opt, handler, *args # :nodoc
    args.empty? ?  handler[] : handler[args[0]]
  rescue => ex
    raise OptionError, "#{opt}: #{ex}"
  end

  # Returns the hash of parsed options and argument values. The +argv+ array
  # is modified: every recognized option and argument is deleted.
  #
  # The +optdef+ hash defines the options and their arguments.
  #
  # Each key is an option name (without "-" chars).
  #
  # The value for a key in +optdef+
  # is used to generate the value for the same key in the options hash
  # returned by this method.
  #
  # If the value has an #arity method and arity > 0, the value is considered to
  # be a handler; it is called with the argument string to return the value
  # associated with the option in the hash returned by the method.
  #
  # If the arity <= 0, the value is considered to be a handler for an option
  # without arguments; it is called with no arguments to return the value of
  # the option.
  #
  # If there is no arity method, the object itself is used as the value of
  # the option.
  #
  # Only one kind of input will cause an exception (not counting exceptions
  # raised by handler code or by bugs):
  #
  # - An option is found at the end of the list, and it requires an argument.
  #   This results in a call to #argument_missing, which by default raises
  #   OptionError.
  #
  def parse_options argv, optdef
    orig = argv.dup; argv.clear
    opts = {}

    loop do
      case (argstr=orig.shift)
      when nil, "--"
        argv.concat orig
        break

      when /^(--)([^=]+)=(.*)/, /^(-)([^-])(.+)/
        short = ($1 == "-"); opt = $2; arg = $3
        unless optdef.key?(opt)
          argv << argstr
          next
        end
        handler = optdef[opt]
        arity = (handler.arity rescue nil)
        opts[opt] =
          case arity
          when nil;   orig.unshift("-#{arg}") if short; handler
          when 0,-1;  orig.unshift("-#{arg}") if short; handle(opt, handler)
          else        handle(opt, handler, arg)
          end

      when /^--(.+)/, /^-(.)$/
        opt = $1
        unless optdef.key?(opt)
          argv << argstr
          next
        end
        handler = optdef[opt]
        arity = (handler.arity rescue nil)
        opts[opt] =
          case arity
          when nil;   handler
          when 0,-1;  handle(opt, handler)
          else        handle(opt, handler, orig.shift || argument_missing(opt))
          end

      else
        argv << argstr
      end
    end

    opts
  end
end

if __FILE__ == $0

  v = 0
  defaults = {
    "v"     => v,
    "port"  => 4000,
    "host"  => "localhost"
  }

  optdef = {
    "x"     => true,
    "y"     => "y",
    "z"     => 3,
    "v"     => proc {v+=1}, # no argument, but call the proc to get the value
    "port"  => proc {|arg| Integer(arg)},
    "n"     => proc {|arg| Integer(arg)},
    "t"     => proc {|arg| Float(arg)},
    "cmd"   => proc {|arg| arg.split(",")}
  }

  ARGV.replace %w{
    -xyzn5 somefile --port 5000 -t -1.23 -vv -v --unrecognized-option
    --cmd=ls,-l otherfile -- --port
  }
  
  begin
    cli_opts = Argos.parse_options(ARGV, optdef)
  rescue Argos::OptionError => ex
    $stderr.puts ex.message
    exit
  end
  
  opts = defaults.merge cli_opts

  p opts
  p ARGV
  unless ARGV.empty?
    puts "Some arg-looking strings were not handled:", *ARGV.grep(/^-./)
  end
  
end

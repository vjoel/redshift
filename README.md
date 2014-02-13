# RedShift #

A framework for simulation of networks of hybrid automata, similar to SHIFT and Lambda-SHIFT. Includes ruby-based DSL for defining simulation components, and ruby/C code generation and runtime.

There's not much [documentation](doc) yet, but plenty of [examples](examples). Some of the original SHIFT papers are available: [Shift: A Formalism and a Programming Language for Dynamic Networks of Hybrid Automata]( http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.32.5913&rep=rep1&type=pdf).

## Requirements ##

RedShift needs ruby (1.8, 1.9, 2.0, 2.1) and a compatible C compiler. If you can build native gems, you're all set.

Some of the examples also use Ruby/Tk and the tkar gem.

## Installation ##

Install as gem:

    gem install ruby

## Env vars ##

If you have a multicore system and are using the gnu toolchain, set

    REDSHIFT_MAKE_ARGS='-j -l2'

or some variation. You'll find that rebuilds of your simulation code go faster.

----

Copyright (C) 2001-2014, Joel VanderWerf, mailto:vjoel@users.sourceforge.net
Distributed under the Ruby license. See www.ruby-lang.org.


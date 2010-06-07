=begin

==class SuperHash

The Ruby inheritance system is a powerful way to organize methods and constants
in a hierarchy of classes and modules. However, it does not provide an easy way
to organize class attributes with inherited values in such a hierarchy. There is no inheritance mechanism that combines:

1. propagation of values to descendant classes;

2. overriding of values by a subclass; and

3. mutability.

The closest approximations in Ruby are class variables, class instance variables, and constants.

A class variable ((({@@var}))) is stored in the base class in which it was
defined. When its value is changed by a subclass, the change propagates to all
subclasses of the base class. The value cannot be overridden just for that
subclass and its descendants. This satisfies 1 and 3, but not 2.

A class instance variable ((({@var}))) can take on a different value in each
subclass, but there is no inheritance mechanism. Its value is privately
accessible by its owner (though it may be exposed by methods). However, the value does not propagate to subclasses. This satisfies 2 and 3, but not 1.

A constant is inherited and can take on different values in subclasses. However it cannot be changed and is always public. This satisfies 1 and 2, but not 3.

(({SuperHash})) solves this class attribute problem and in addition is a
general mechanism for defining attribute inheritance structures among objects
of any type, not just classes. An example of the former is (({StateObject})),
in (({examples/state-object.rb})). An example of the latter is
(({AttributedNode})), in (({examples/attributed-node.rb})).

A superhash is simply a hash bundled with a list of parents, which can be
hashes or other hash-like objects. For all lookup methods, like (({[]})),
(({each})), (({size})), and so on, the superhash behaves as if the parent hash
entries were included in it. The inheritance search is depth-first, and in the
same order as the parents list.

Destructive methods, such as (({[]=})) and (({delete})), do not affect the
parent (however, see (({rehash})) below), but attempt to emulate the expected
effect by changing the superhash itself. Operations on a parent are immdiately
reflected in the child; the parent's data is referenced, not copied, by the
child.

The equality semantics of (({SuperHash})) is the same as that of (({Hash})).
The (({==})) method returns true if and only if the receiver and the argument
have the same (in the sense of (({==}))) key-value pairs. The (({eql?}))
method is inherited from (({Object})). Naturally, (({SuperHash})) includes the
(({Enumerable})) module.

Note that (({SuperHash})) is not very efficient. Because (({SuperHash})) is
dynamic and flexible, even an operation as simple as (({size})) requires
sending (({size})) messages to the parents. Also, the current implementation
emphasizes simplicity over speed. For instance, (({each})) requires
constructing the set of all keys, which requires collecting key sets for
parents, and then taking their union.

===class method

---SuperHash.new parents = [], default = nil

The (({parents})) argument can be an enumerable collection of hash-like
objects, or a single hash-like object, or [] or nil. The hash-like objects must
support (({find})), (({collect})), (({keys})), (({key?})), and (({[]})).

The precedence order of parents is the same as their order in the (({parents}))
array. In other words, the first parent in the list overrides later ones, and
so on. Inheritance is by depth first.

If the (({default})) argument is specified, it affects the (({SuperHash})) just
like the (({default})) argument in the (({Hash})) constructor. The default
behavior of the child replaces the default behaviors of the parents.

===overridden instance methods

The SuperHash instance methods provide a hash-like interface. Hash methods which
need special explanation are documented below.

---SuperHash#clear

The implementation of (({clear})) is to simply call (({delete_if {true}})).

---SuperHash#delete(key)
---SuperHash#delete(key) { |key| block }
---SuperHash#delete_if { |key, value| block }

If the key is inherited, these methods simply associate the default value to
the key in the (({SuperHash})). Note that if the default is changed after the
deletion, the key-value pair is not updated to reflect the change--the value
will still be the old default.

---SuperHash#empty?
---SuperHash#size

Note that (({superhash.clear.empty?})) will not return (({true})) if there are
inherited keys. The (({SuperHash})) needs to remember which parent keys have
been deleted, and this is not easily distinguishable from the case in which
those keys have been explicitly associated with (({nil})) (or the default
value). Similar remarks apply to (({size})).

---SuperHash#invert
---SuperHash#to_hash

Returns a (({Hash})), in the first case with inverted key-value pairs, in the
second case with the same key-value pairs, as the receiver.

---SuperHash#rehash

Rehashes the receiver's (({own})) hash and rehashes all parents (if they
respond to (({rehash}))). Note that this is the only (({SuperHash})) method
that modifies the parent objects.

---SuperHash#replace(hash)

Replaces the receiver's (({own})) hash with the argument, and replaces the
receiver's parent array with the empty array.

---SuperHash#shift

As long as the (({own})) hash has entries, shifts them out and returns them.
Raises (({ParentImmutableError})) if the receiver's (({own})) hash is empty.

===new instance methods

(({SuperHash})) defines some instance methods that are not available in
(({Hash})).

---SuperHash#inherits_key? k

Returns (({true})) if and only if (({k})) is a key in a parent but not in the
receiver's (({own})) hash.

---SuperHash#own

Returns the hash of key-value pairs that belong to the superhash and are not
inherited.

---SuperHash#own_keys

Returns the array of keys in the (({own})) hash.

---SuperHash#owns_key? k

Returns (({true})) if and only if (({k})) is a key in the (({own})) hash.

==version

SuperHash 0.3

The current version of this software can be found at 
((<"http://redshift.sourceforge.net/superhash
"|URL:http://redshift.sourceforge.net/superhash>)).

==license
This software is distributed under the Ruby license.
See ((<"http://www.ruby-lang.org"|URL:http://www.ruby-lang.org>)).

==author
Joel VanderWerf,
((<vjoel@users.sourceforge.net|URL:mailto:vjoel@users.sourceforge.net>))

=end

class SuperHash
  include Enumerable
  
  attr_reader :parents
  
  def initialize parents = [], default = nil
    @hash = Hash.new default
    if parents == nil
      @parents = []
    elsif parents.respond_to? :key?
      @parents = [parents]
    else
      @parents = parents
    end
  end
  
  # methods that are not overrides of Hash methods
  
  def inherits_key? k
    !(@hash.key? k) && (!! @parents.find {|parent| parent.key? k } )
  end

  def own
    @hash
  end

  def own_keys
    @hash.keys
  end
  
  def owns_key? k
    @hash.key? k
  end

  # methods that override Hash methods

  def ==(other)
    return false unless other.respond_to? :size and
                        size == other.size      and
                        other.respond_to? :[]
    each { |key, value| return false unless self[key] == other[key] }
    return true
  end

  def [](key)
    fetch(key) {default}
  end
  
  def []=(key, value)
    @hash[key] = value
  end
  alias store []=
  
  def clear
    delete_if {true}
  end
  
  def default
    @hash.default
  end
  
  def default=(value)
    @hash.default = value
  end
  
  def delete(key)
    if key? key
      @hash.delete(key) do
        value = fetch(key)
        @hash[key] = default
        value
      end
    else
      block_given? ? (yield key) : default
    end
  end
  
  def delete_if
    each do |key, value|
      if yield key, value
        @hash.delete(key) { @hash[key] = default }
      end
    end
  end

  def each
    keys.each { |k| yield k, fetch(k) }
    self
  end
  alias each_pair each
  
  def each_key
    keys.each { |k| yield k }
    self
  end
    
  def each_value
    keys.each { |k| yield fetch(k) }
    self
  end
    
  def empty?
    @hash.empty? && ( not @parents.find {|parent| not parent.empty?} )
  end
  
  def fetch(*args)
    case args.size
    when 1
      key, = args
      @hash.fetch(key) {
        @parents.each do |parent|
          begin
            return parent.fetch(key)
          rescue IndexError
          end
        end
        if block_given?
          yield key
        else
          raise IndexError, "key not found"
        end
      }
    when 2
      if block_given?
        raise ArgumentError, "wrong # of arguments"
      end
      key, default_object = args
      @hash.fetch(key) {
        @parents.each do |parent|
          begin
            return parent.fetch(key)
          rescue IndexError
          end
        end
        return default_object
      }
    else
      raise ArgumentError, "wrong # of arguments(#{args.size} for 2)"
    end
  end

  def has_value? val
    each { |k,v| return true if val == v }
    return false
  end
  alias value? has_value?
  
  def index val
    each { |k,v| return k if val == v }
    return false
  end
  
  def indexes(*ks)
    ks.collect { |k| index k }
  end
  alias indices indexes
  
  def invert
    h = {}
    keys.each { |k| h[fetch(k)] = k }
    h
  end
  
  def key? k
    (@hash.key? k) || (!! @parents.find {|parent| parent.key?(k)} )
  end
  alias has_key? key?
  alias include? key?
  alias member?  key?

  def keys
    (@hash.keys + (@parents.collect { |parent| parent.keys }).flatten).uniq
  end
  
  def rehash
    @hash.rehash
    @parents.each { |parent| parent.rehash if parent.respond_to? :rehash }
    self
  end
  
  def reject
    dup.delete_if { |k, v| yield k, v }   ## or is '&Proc.new' faster?
  end
  
  def reject!
    changed = false
    
    each do |key, value|
      if yield key, value
        changed = true
        @hash.delete(key) { @hash[key] = default }
      end
    end
    
    changed ? self : nil
  end
  
  def replace hash
    @hash.replace hash
    @parents.replace []
  end
  
  class ParentImmutableError < StandardError; end
  
  def shift
    if @hash.empty?
      raise ParentImmutableError, "Attempted to shift data out of parent"
    else
      @hash.shift
    end
  end
  
  def size
    keys.size
  end
  alias length size
  
  def sort
    if block_given?
      to_a.sort { |x, y| yield x, y }   ## or is '&Proc.new' faster?
    else
      to_a.sort
    end
  end
  
  def to_a
    to_hash.to_a
  end
  
  def to_hash
    h = {}
    keys.each { |k| h[k] = fetch(k) }
    h
  end
  
  def to_s
    to_hash.to_s
  end
  
  def update h
    @hash.update h
    self
  end
    
  def values
    keys.collect { |k| self[k] }
  end

end

class Class
private
  def class_superhash(*vars)
    for var in vars
      class_eval %{
        @#{var} = Hash.new
        def self.#{var}
          @#{var} ||= SuperHash.new(superclass.#{var})
        end
      }
    end
  end

  # A superhash of key-value pairs in which the value is a superhash
  # which inherits from the key-indexed superhash in the superclass.
  def class_superhash2(*vars)
    for var in vars
      class_eval %{
        @#{var} = Hash.new
        def self.#{var}(arg = nil)
          @#{var} ||= SuperHash.new(superclass.#{var})
          if arg
            if self == #{self.name}
              unless @#{var}.has_key? arg
                @#{var}[arg] = Hash.new
              end
            else
              unless @#{var}.owns_key? arg
                @#{var}[arg] = SuperHash.new(superclass.#{var}(arg))
              end
            end
            @#{var}[arg]
          else
            @#{var}
          end
        end
      }
    end
  end
end

class Object
  def diff other, &block
    d = other - self
    if block
      block.call d
    end
    d
  end
  
  def filter
    (yield self) && self
  end
end

class NilClass
  def diff other, &block
    0
  end
end

class Array
  def diff other, &block
    a = (0...[self.size, (other ? other.size : 0)].min).map do |i|
      self[i].diff(other[i], &block)
    end
    if block
      block.call a, other.size - self.size
    end
    a
  end

  def filter(&block)
    aa = inject([]) do |a, val|
      v = val.filter(&block)
      a << v if v
      a
    end
    aa.empty? ?  nil : aa
  end
end

class Hash
  def diff other, &block
    ha = (self.keys & other.keys).inject({}) do |h,k|
      h[k] = self[k].diff(other[k], &block); h
    end
    if block
      block.call ha, self.keys - other.keys, other.keys - self.keys
    end
    ha
  end

  def filter(&block)
    ha = inject({}) do |h, (key, val)|
      v = val.filter(&block)
      h[key] = v if v
      h
    end
    ha.empty? ?  nil : ha
  end
end

if __FILE__ == $0

#r = [{0=>1, 2=>3, 1=>[-1=>-2, 7=>8]}].filter {|x| x>1}
#p r
#exit

  a = {
    "foo" => [ {1=>2}, {3=>4.2} ],
    "bar" => [ 4, 5, [6, 8] ]
  }

  b = {
    "foo" => [ {1=>2}, {3=>4} ],
    "bar" => [ 4, 7, [6, 9] ]
  }

  require 'yaml'

  y a.diff(b).filter {|x| x > -0.1}

end

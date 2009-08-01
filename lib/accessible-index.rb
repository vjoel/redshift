module AccessibleIndex
  def index_accessor(h)
    h.each do |sym, idx|
      define_method sym do
        self[idx]
      end
      define_method "#{sym}=" do |val|
        self[idx] = val
      end
    end
  end

  def index_reader(h)
    h.each do |sym, idx|
      define_method sym do
        self[idx]
      end
    end
  end

  def index_writer(h)
    h.each do |sym, idx|
      define_method "#{sym}=" do |val|
        self[idx] = val
      end
    end
  end
end

if __FILE__ == $0

  class TestArray < Array
    extend AccessibleIndex

    index_accessor :a => 3, :b => 7
  end

  ta = TestArray[0,1,2,3,4,5,6,7,8,9,10]#.new((0..10).to_a)

  p ta

  ta.a = "three"
  ta.b = "seven"

  p ta

end

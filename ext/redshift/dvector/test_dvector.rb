require './dvector'
require 'test/unit'

DVector = RedShift::DVector

class TestDVector < Test::Unit::TestCase
  def make_dvs n
    assert_nothing_thrown do
      n.times do
        DVector.new
      end
    end
  end

  def test_gc
    GC.start
    n = ObjectSpace.each_object(DVector){}

    assert_nothing_thrown do
      make_dvs 100
    end
    
    GC.start
    n2 = ObjectSpace.each_object(DVector){}

    assert((0..n+1) === n2, "Not in #{0}..#{n+1}: #{n2}")
  end
  
  def test_gc_stress
    GC.stress = true
    assert_nothing_thrown do
      make_dvs 10
    end
  ensure
    GC.stress = false
  end
  
  def test_push_pop
    dv = DVector.new
    assert_nothing_thrown do
      dv.push(1)
      dv.push(2)
      dv.push(3)
    end
    assert_equal(3, dv.pop)
    assert_equal(2, dv.pop)
    assert_equal(1, dv.pop)
    assert_equal(nil, dv.pop)
  end
  
  def test_each
    dv = DVector[1, 2, 3]
    a = []
    dv.each do |x|
      a << x
    end
    assert_equal([1,2,3], a)
  end
  
  def test_to_a
    dv = DVector[1, 2, 3]
    assert_equal([1,2,3], dv.to_a)
  end
  
  def test_length
    dv = DVector[1, 2, 3]
    assert_equal(3, dv.length)
    dv = DVector.new
    assert_equal(0, dv.length)
  end
  
  def test_equal
    dv1 = DVector[1, 2, 3]
    dv2 = DVector[1, 2, 3, 4]
    assert_equal(false, dv1 == dv2)
    assert_equal(false, dv1 == [1,2,3])
    assert_equal(false, dv1 == 123)
    assert_equal(true, dv1 == dv1)
    assert_equal(true, DVector.new == DVector.new)
    assert_equal(true, DVector[1] == DVector[1.0])
  end
  
  def test_eql
    dv1 = DVector[1, 2, 3]
    dv2 = DVector[1, 2, 3, 4]
    assert_equal(false, dv1.eql?(dv2))
    assert_equal(false, dv1.eql?([1,2,3]))
    assert_equal(false, dv1.eql?(123))
    assert_equal(true, dv1.eql?(dv1))
    assert_equal(true, DVector.new.eql?(DVector.new))
    assert_equal(false, DVector[1].eql?(DVector[1.0]))
  end
  
  def test_hash
    h = {}
    h[DVector[1,2,3]] = true
    assert_equal(true, h[DVector[1,2,3]])
    assert_equal(nil, h[DVector[1,2,3,4]])
  end
  
  def test_dup
    DVector[1,2,3] == DVector[1,2,3].dup
  end
  
  def test_marshal
    dv = DVector[1, 2, 3]
    dv2 = Marshal.load(Marshal.dump(dv))
    assert_equal(dv.to_a, dv2.to_a)
  end
end

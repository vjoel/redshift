require 'redshift/dvector-float/dvector-float'
require 'minitest/autorun'

DVectorFloat = RedShift::DVectorFloat

class TestDVectorFloat < Minitest::Test
  def make_dvs n
    #assert_nothing_thrown do
    n.times do
      DVectorFloat.new
    end
  end

  def test_gc
    GC.start
    n = ObjectSpace.each_object(DVectorFloat){}

    #assert_nothing_thrown
    make_dvs 100
    
    GC.start
    n2 = ObjectSpace.each_object(DVectorFloat){}

    assert((0..n+1) === n2, "Not in #{0}..#{n+1}: #{n2}")
  end
  
  def test_gc_stress
    GC.stress = true
    #assert_nothing_thrown
    make_dvs 10
  ensure
    GC.stress = false
  end
  
  def test_push_pop
    dv = DVectorFloat.new
    #assert_nothing_thrown
    dv.push(1)
    dv.push(2.567)
    dv.push(3)

    assert_equal(3, dv.pop)
    assert_in_delta(2.567, dv.pop, 0.01)
    assert_equal(1, dv.pop)
    assert_equal(nil, dv.pop)
  end
  
  def test_each
    dv = DVectorFloat[1, 2.567, 3]
    a = []
    dv.each do |x|
      a << x
    end
    [1,2.567,3].zip a do |x,y|
      assert_in_delta(x, y, 0.01)
    end
  end
  
  def test_to_a
    dv = DVectorFloat[1, 2.567, 3]
    [1,2.567,3].zip dv.to_a do |x,y|
      assert_in_delta(x, y, 0.01)
    end
  end
  
  def test_length
    dv = DVectorFloat[1, 2.567, 3]
    assert_equal(3, dv.length)
    dv = DVectorFloat.new
    assert_equal(0, dv.length)
  end
  
  def test_equal
    dv1 = DVectorFloat[1, 2.567, 3]
    dv2 = DVectorFloat[1, 2.567, 3, 4]
    assert_equal(false, dv1 == dv2)
    assert_equal(false, dv1 == [1,2.567,3])
    assert_equal(false, dv1 == 123)
    assert_equal(true, dv1 == dv1)
    assert_equal(true, DVectorFloat.new == DVectorFloat.new)
    assert_equal(true, DVectorFloat[1] == DVectorFloat[1.0])
  end
  
  def test_eql
    dv1 = DVectorFloat[1, 2.567, 3]
    dv2 = DVectorFloat[1, 2.567, 3, 4]
    assert_equal(false, dv1.eql?(dv2))
    assert_equal(false, dv1.eql?([1,2.567,3]))
    assert_equal(false, dv1.eql?(123))
    assert_equal(true, dv1.eql?(dv1))
    assert_equal(true, DVectorFloat.new.eql?(DVectorFloat.new))
  end
  
  def test_hash
    h = {}
    h[DVectorFloat[1,2.567,3]] = true
    assert_equal(true, h[DVectorFloat[1,2.567,3]])
    assert_equal(nil, h[DVectorFloat[1,2.567,3,4]])
  end
  
  def test_dup
    DVectorFloat[1,2.567,3] == DVectorFloat[1,2.567,3].dup
  end
  
  def test_marshal
    dv = DVectorFloat[1, 2.567, 3]
    dv2 = Marshal.load(Marshal.dump(dv))
    assert_equal(dv.to_a, dv2.to_a)
  end
end

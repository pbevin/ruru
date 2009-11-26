$LOAD_PATH << File.join(File.dirname(__FILE__),"..","interp")

require 'ruru'

# We describe a small piece of sample code that motivates writing the interpreter.
# The code simply calculates the scalar product of two vectors using a while loop.
describe "Scalar Product calculator example code" do
  attr_reader :r

  before(:each) do
    prog = <<-END
      def xprod(a, b)
        i, prod = 0, 0
        while i < a.size
          prod += a[i] * b[i]
          i += 1
        end
        return prod
      end
    END
    @r = ruru(prog)
  end

  # Translation layer between Ruby code and low-level objects.
  def xprod(a, b)
    a = a.map{ |x| RuFixnum.new(x) }
    b = b.map{ |x| RuFixnum.new(x) }
    r.call(:xprod, RuArray.new(a), RuArray.new(b)).__val
  end

  it "evaluates to 0 when the arrays are empty" do
    xprod([], []).should == 0
  end

  it "adds up a when b is all 1" do
    xprod([1,2,3,4,5], [1,1,1,1,1]).should == 15
  end

  it "throws an exception when array b is too short" do
    lambda { xprod([1], []) }.should raise_error("Array bounds")
  end
end
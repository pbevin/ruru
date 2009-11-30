class AssertionFailure < StandardError
end
 
class Object
  def assert(bool, message = 'assertion failure')
    raise AssertionFailure.new(message) unless bool
  end
end

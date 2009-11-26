require 'rubygems'
require 'ruby_parser'
require 'pp'

# Support inline assertions.
class AssertionFailure < StandardError
end

class Object
  def assert(bool, message = 'assertion failure')
    raise AssertionFailure.new(message) unless bool
  end
end

# Ruru object class
class RuObj
end

class Ruru
  Qnil = RuObj.new
  Qtrue = RuObj.new
  Qfalse = RuObj.new

  attr_reader :context

  def initialize(code, context)
    @context = context
    if Sexp === code
      @parsed = code
    else
      @parsed = RubyParser.new.parse(code)
      # pp @parsed
    end
  end

  # Evaluate a sexp by finding the top-level form and proceeding down the tree.
  def eval(sexp = @parsed)
    type, *args = sexp
    case type
    when :defn
      context.define_method(sexp[1], sexp[2].drop(1), sexp[3].dup)
    when :scope
      assert args.size == 1, ":scope with wrong args #{args.inspect}"
      eval(args[0])
    when :block
      retval = nil
      args.each do |arg|
        retval = eval(arg)
      end
      retval
    when :lit
      RuFixnum.new(args[0])
    when :lvar
      context.get_variable(args[0])
    when :lasgn
      var, expr = args
      val = eval(expr)
      context.set_variable(var, val)
    when :masgn
      lhs, rhs = args
      lhs = lhs.drop(1)
      rhs = rhs.drop(1)
      lhs.zip(rhs).each { |l,r| context.set_variable(l[1], eval(r)) }
    when :while
      cond, body = args
      while eval(cond)
        eval(body)
      end
      Qnil
    when :call
      lhs, method, arglist = args
      apply(lhs, method, arglist.drop(1))
    when :return
      eval(args[0])
    else
      raise "Parse error for #{sexp.inspect}"
    end
  end

  # 
  def apply(obj, method, args)
    obj = eval(obj)
    args = args.map { |x| eval(x) }
    return obj.apply(method, args)
  end

  def call(method, *args)
    context.find_method(method).call(*args)
  end
end

def ruru(code, context = RuContext.new)
  ruru = Ruru.new(code, context)
  ruru.eval
  ruru
end

class RuContext
  def initialize
    @methods = {}
    @variables = {}
  end

  def define_method(name, args, body)
    @methods[name] = RuMethod.new(self, args, body)
  end

  def find_method(name)
    @methods[name]
  end

  def set_variable(var, value)
    @variables[var] = value
  end

  def get_variable(var)
    @variables[var]
  end
end

class RuMethod
  def initialize(context, params, body)
    @params = params
    @body = body
    @context = context
  end

  attr_reader :params, :body, :context

  def call(*args)
    params.zip(args).each do |param, arg|
      context.set_variable(param, arg)
    end
    Ruru.new(body, context).eval
  end
end

class RuFixnum
  def initialize(val)
    @val = val
  end

  def __val
    @val
  end

  def apply(method, args)
    arg = args[0]
    case method
    when :<
      __val < arg.__val  # sb RuBoolean
    when :+
      RuFixnum.new(__val + arg.__val)
    when :*
      RuFixnum.new(__val * arg.__val)
    else
      raise "Method #{method}"
    end
  end
end

class RuArray
  def initialize(arr)
    @vals = arr
  end

  def apply(method, args)
    arg = args[0]
    case method
    when :size
      RuFixnum.new(@vals.size)
    when :[]
      i = args[0].__val
      raise "Array bounds" if i < 0 || i >= @vals.size
      @vals[i]
    else
      raise "Method #{method}"
    end
  end
end
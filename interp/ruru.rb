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
class RuObject
  attr_reader :ru_class

  def initialize(cls = nil)
    @ru_class = cls
    @methods = {}
    @constants = {}
    @ivars = {}
  end

  def set_constant(name, value)
    @constants[name.to_sym] = value
  end

  def get_constant(name)
    @constants[name.to_sym]
  end

  def get_instance_variable(name)
    @ivars[name]
  end

  def set_instance_variable(name, value)
    @ivars[name] = value
  end

  def apply(method, *args)
    ru_class.find_method(method).call(*args)
  end
end

class Ruru
  Qnil = RuObject.new
  Qtrue = RuObject.new
  Qfalse = RuObject.new

  attr_reader :context

  def initialize(code, context)
    @context = context
    assert RuContext === context
    if Sexp === code
      @parsed = code
    else
      @parsed = RubyParser.new.parse(code)
      pp @parsed
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
    when :ivar
      context.get_instance_variable(args[0])
    when :iasgn
      context.set_instance_variable(args[0], eval(args[1]))
    when :self
      context.ru_self
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
      context.setting_self_to(lhs) do
        apply(lhs, method, arglist.drop(1))
      end
    when :return
      eval(args[0])
    when :class
      name, parent, body = args
      context.open_class(name, parent)
      eval(body)
      context.end_class(name)
    else
      raise "Parse error for #{sexp.inspect}"
    end
  end

  def apply(obj, method, args)
    obj = eval(obj)
    args = args.map { |x| eval(x) }
    return obj.apply(method, *args)
  end

  def call(method, *args)
    context.find_method(method).call(*args)
  end

  def new_object(cls, *args)
    class_object = context.get_constant(cls.to_sym)
    class_object.apply(:new, args)
  end

  def instance_eval(new_self, expr)
    context.setting_self_to(new_self) do
      sexp = RubyParser.new.parse(expr)
      eval(sexp)
    end
  end
end

def ruru(code, context = RuContext.new)
  ruru = Ruru.new(code, context)
  ruru.eval
  ruru
end

class RuContext
  def initialize(context = nil)
    assert context == nil || BaseContext === context
    @context = context || BaseContext.new(:self => RuObject.new(RuClass.new('TopLevel')))
  end

  def push(new_self)
    new_context = BaseContext.new(:self => new_self, :parent => @context)
    @context = new_context
  end

  def pop
    @context = @context.parent
  end

  def setting_self_to(new_self)
    push(new_self)
    v = yield
    pop
    v
  end

  def method_missing(meth, *args, &blk)
    @context.send(meth, *args, &blk)
  end

  def open_class(name, parent)
    cls = RuClass.new(name, parent)
    @context.set_constant(name.to_sym, cls)
    push(cls)
  end

  def end_class(name)
    pop
  end

  class BaseContext
    def initialize(args = {})
      @ru_self = args[:self]
      @parent = args[:parent]
      @variables = {}
    end

    attr_reader :parent, :ru_self

    def set_variable(var, value)
      @variables[var] = value
    end

    def get_variable(var)
      if @variables.include?(var)
        @variables[var]
      elsif @parent
        parent.get_variable(var)
      else
        nil
      end
    end

    def get_instance_variable(var)
      @ru_self.get_instance_variable(var)
    end

    def set_instance_variable(var, val)
      @ru_self.set_instance_variable(var, val)
    end

    def define_method(name, args, body)
      @ru_self.ru_class.define_method(name, RuMethod.new(RuContext.new(self), args, body))
    end

    def find_method(name)
      @ru_self.ru_class.find_method(name)
    end

    def set_constant(name, value)
      @ru_self.set_constant(name, value)
    end

    def get_constant(name)
      @ru_self.get_constant(name)
    end
  end
end

class RuMethod
  def initialize(context, params, body)
    assert RuContext === context
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

  def apply(method, *args)
    arg = args[0]
    assert RuFixnum === arg
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

  def apply(method, *args)
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

class RuClass < RuObject
  attr_reader :name
  def initialize(name, parent = nil)
    @name = name
    super(self)
  end

  def apply(method, args)
    case method
    when :new
      obj = RuObject.new(self)
      obj.apply(:initialize, *args)
      return obj
    else
      super
    end
  end

  def ru_class
    self
  end

  def define_method(name, method)
    @methods[name] = method
  end

  def find_method(name)
    @methods[name]
  end
end
require 'rubygems'
require 'ruby_parser'
require 'pp'

class RuObject; end
class RuContext; end

class Ruru
  attr_accessor :recv
  attr_accessor :context

  def initialize
    @recv = @main = RuObject.new(nil)
    @recv.set_constant(:main, "main")
    @recv.ru_class = @obj_class
    @context = RuContext.new
  end

  def run(prog)
    prog = RubyParser.new.parse(prog)
    @prog = prog
    eval(prog)
  end

  def eval(sexp)
    type, *args = sexp
    case type
    when :defn
      name, arglist, body = args
      arglist = arglist.drop(1)
      recv.define_method(RuMethod.new(name, arglist, body))
    when :call
      new_recv, method_name, arglist = args
      new_recv = eval(new_recv) if new_recv
      call(new_recv, method_name, arglist.drop(1).map { |a| eval(a) })
    when :scope
      eval(args[0])
    when :class
      name, parent_name, body = args
      parent = parent_name ? eval(parent_name) : nil
      open_class(name, parent, body)
    when :block
      v = nil
      args.each do |stmt|
        v = eval(stmt)
      end
      v
    when :lasgn
      var, value = args
      value = eval(value)
      context.set_variable(var, value)
    when :const
      recv.get_constant(args[0])
    when :masgn
      lhs, rhs = args
      lhs = lhs.drop(1)
      rhs = rhs.drop(1)
      lhs.zip(rhs).each { |l,r| context.set_variable(l[1], eval(r)) }
    when :lit
      RuFixnum.new(args[0])
    when :str
      args[0]  ###
    when :while
      cond, body = args
      while eval(cond)
        eval(body)
      end
      nil
    when :lvar
      var = args[0]
      context.get_variable(var)
    when :iasgn
      var, value = args
      recv.set_instance_variable(var, eval(value))
    when :ivar
      recv.get_instance_variable(args[0])
    when :array
      arr = args.map { |a| eval(a) }
      RuArray.new(arr)
    when :return
      eval(args[0])
    when :super
      arglist = args.map { |a| eval(a) }
      call(recv, context.current_method, arglist, context.current_class.parent)
    else
      raise "eval: Unrecognized sexp #{sexp.inspect}"
    end
  end

  def call(new_recv, method_name, args, cls = nil)
    if (!new_recv)
      new_recv = @recv
    end

    cls = new_recv.eigenclass_or_class if !cls
    method = cls.find_method_cls(method_name)

    if method
      old_recv = @recv
      @recv = new_recv

      ## XXX: scope push
      method.args.zip(args).each do |name, value|
        context.set_variable(name, value)
      end
      context.current_method = method_name
      context.current_class = cls
      v = eval(method.body)
      @recv = old_recv
      context.current_class = nil
      context.current_method = nil
      v
    elsif new_recv.ru_class == RuClass.instance(:class) && method_name == :new
      obj = RuObject.new(new_recv)
      call(obj, :initialize, args)
      obj
    else
      begin
        new_recv.send(method_name, *args)
      rescue NoMethodError
        raise "No method #{method_name.inspect} in #{new_recv.inspect}"
      end
    end
  end

  def create_class(class_name, parent)
    parent ||= recv.get_constant(:Object)
    if class_obj = recv.get_constant(class_name)
      return class_obj
    end
    class_obj = RuClass.new(class_name, parent) ### parent is str, not RuClass
    recv.set_constant(class_name, class_obj)
    class_obj
  end

  def open_class(class_name, parent, body)
    class_obj = create_class(class_name, parent)
    old_recv = recv
    @recv = class_obj
    v = eval(body)
    @recv = old_recv
    v
  end
end

def ruru(prog)
  r = Ruru.new
  r.run(prog)
  r
end

RuMethod = Struct.new(:name, :args, :body)
NativeMethod = Struct.new(:name, :op)

class RuObject
  attr_accessor :ru_class
  attr_accessor :special_name

  def initialize(cls = nil)
    @ivars = {}
    @constants = {}
    @ru_class = cls
  end

  def define_method(method)
    @eigenclass ||= RuClass.new("eigenclass", @ru_class)
    @eigenclass.define_method(method)
  end

  def find_method(name)
    raise "Object #{self.inspect} has no eigenclass and no class" if !eigenclass_or_class
    eigenclass_or_class.find_method_cls(name)
  end

  def eigenclass_or_class
    (@eigenclass || @ru_class)
  end

  def set_constant(name, value)
    @constants[name.to_sym] = value
  end

  def get_constant(name)
    @constants[name.to_sym]
  end

  def set_instance_variable(name, value)
    @ivars[name] = value
  end

  def get_instance_variable(name)
    @ivars[name]
  end
end


class RuClass < RuObject
  attr_reader :parent
  attr_accessor :name

  def parent=(parent)
    @parent = parent
    @methods = {}
  end

  @@cls_cls = RuClass.new
  @@cls_cls.ru_class = @@cls_cls

  def initialize(name, parent = nil)
    super(@@cls_cls)
    @name = name
    self.parent = parent
  end

  @@obj_cls = RuClass.new("Object", nil)
  @@mod_cls = RuClass.new("Module", @@obj_cls)
  @@arr_cls = RuClass.new("Array", @@obj_cls)
  @@fix_cls = RuClass.new("Fixnum", @@obj_cls)

  @@cls_cls.parent = @@mod_cls

  @@classes = {
    :object => @@obj_cls,
    :class => @@cls_cls,
    :module => @@mod_cls,
    :array => @@arr_cls,
    :fixnum => @@fix_cls
  }

  def self.instance(type = :class)
    @@classes[type]
  end

  def define_method(method)
    @methods[method.name] = method
  end

  def find_method_cls(name)
    m = @methods[name]
    if m
      # puts "Method #{name} found in #{@name}"
      return m
    else
      # puts "No method #{name} on #{@name}, parent is #{@parent}"
      @parent && @parent.find_method_cls(name)
    end
  end

  def inspect
    "class##{@name}"
  end
end

class RuContext
  attr_accessor :current_class, :current_method
  def initialize
    @vars = {}
  end

  def set_variable(name, value)
    @vars[name] = value
  end

  def get_variable(name)
    @vars[name]
  end
end

class RuArray < RuObject
  def initialize(arr)
    @arr = arr
    super(RuClass.instance(:array))
  end

  def size
    RuFixnum.new(@arr.size)
  end

  def [](idx)
    i = idx.val
    if i < 0 || i >= @arr.size
      raise "Array bounds"
    end
    @arr[idx.val]
  end
end

class RuFixnum < RuObject
  attr_reader :val
  def initialize(val)
    @val = val
    super(RuClass.instance(:fixnum))
  end

  def <(other)
    val < other.val
  end

  def +(other)
    RuFixnum.new(val + other.val)
  end

  def *(other)
    RuFixnum.new(val * other.val)
  end
end
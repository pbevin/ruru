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
    @recv.set_constant(:main, "xx")
    @recv.ru_class = @obj_class
    @context = RuContext.new
  end

  def run(prog)
    if String === prog
      prog = RubyParser.new.parse(prog)
    end
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
      open_class(name, parent_name, body)
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
    else
      raise "eval: Unrecognized sexp #{sexp.inspect}"
    end
  end

  def call(new_recv, method_name, args)
    if (!new_recv)
      new_recv = @recv
    end

    method = new_recv.find_method(method_name)

    if method
      old_recv = @recv
      @recv = new_recv

      ## XXX: scope push
      method.args.zip(args).each do |name, value|
        context.set_variable(name, value)
      end
      v = eval(method.body)
      @recv = old_recv
      v
    elsif new_recv.ru_class == RuClass.instance(:class) && method_name == :new
      obj = RuObject.new(new_recv)
      call(obj, :initialize, args)
      obj
    elsif new_recv.ru_class == RuClass.instance(:array)
      case method_name
      when :size
        new_recv.size
      when :[]
        new_recv[args[0]]
      else
        raise "No method #{method_name.inspect} in Array"
      end
    elsif new_recv.ru_class == RuClass.instance(:fixnum)
      case method_name
      when :<
        new_recv.val < args[0].val
      when :*
        RuFixnum.new(new_recv.val * args[0].val)
      when :+
        RuFixnum.new(new_recv.val + args[0].val)
      else
        raise "No method #{method_name.inspect} in Fixnum"
      end
    else
      raise "No method #{method_name.inspect} defined on #{new_recv.inspect}, #{@main.inspect}, #{@prog}"
    end
  end

  def create_class(class_name, parent)
    parent ||= recv.get_constant(:Object)
    # puts "Creating class #{class_name} with parent #{parent}"
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
    raise "oops #{name}" if !@eigenclass && !@ru_class
    (@eigenclass || @ru_class).find_method_cls(name)
  end

  def set_constant(name, value)
    @constants[name.to_sym] = value
  end

  def get_constant(name)
    @constants[name.to_sym]
  end

  def set_instance_variable(name, value)
    @ivars[name] = value
    # p "isetvar n=#{name} v=#{value.inspect} me=#{self.inspect}"
  end

  def get_instance_variable(name)
    # p "ivar #{name} #{self.inspect}"
    @ivars[name]
  end
end


class RuClass < RuObject
  attr_reader :parent

  def parent=(parent)
    @parent = parent
    @methods = {}
  end

  # @@cls_cls = RuClass.new
  # @@obj_cls = RuObject.new(@@cls_cls)
  # @@cls_cls.ru_class = @@cls_cls
  @@obj_cls = RuClass.new("Object")
  @@cls_cls = RuClass.new("Class")
  @@mod_cls = RuClass.new("Module")
  @@arr_cls = RuClass.new("Array")
  @@fix_cls = RuClass.new("Fixnum")
  [@@obj_cls, @@cls_cls, @@mod_cls, @@arr_cls, @@fix_cls].each { |c| c.ru_class = @cls_cls }
  @@obj_cls.parent = nil
  @@mod_cls.parent = @@obj_cls
  @@cls_cls.parent = @@mod_cls
  @@arr_cls.parent = @@obj_cls
  @@fix_cls.parent = @@obj_cls

  @@classes = {
    :object => @@obj_cls,
    :class => @@cls_cls,
    :module => @@mod_cls,
    :array => @@arr_cls,
    :fixnum => @@fix_cls
  }

  def initialize(name, parent = nil)
    super(@@cls_cls)
    @name = name
    self.parent = parent
  end

  def self.instance(type = :class)
    @@classes[type]
  end

  def define_method(method)
    @methods[method.name] = method
  end

  def native(methods = {})
    methods.each do |name, impl|
      define_method(NativeMethod.new(name, impl))
    end
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
end
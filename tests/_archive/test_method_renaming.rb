# frozen_string_literal: true

require_relative 'test_helper'

class TestMethodRenaming < Minitest::Test
  include MinifyTestHelper

  # ===========================================
  # Group 1: Endless Method / Control Flow / Unless-Else + attr_accessor + Unless
  # ===========================================

  def setup_group1
    @group1 ||= minify_code(<<~RUBY)

      def greet(name)
        puts name
      end
      greet("hello")

      def work(x)
        y = x + 1
        puts y
      end
      work(5)

      def decide_if(x)
        if x > 0
          puts "positive"
          return x
        else
          puts "non-positive"
          return -x
        end
      end
      puts decide_if(5)
      puts decide_if(-3)

      def decide_unless(x)
        unless x > 0
          puts "non-positive"
          return -x
        else
          puts "positive"
          return x
        end
      end
      puts decide_unless(5)
      puts decide_unless(-3)

      def check(x)
        if x > 0
          y = x * 2
          return y
        end
        0
      end
      puts check(3)
      puts check(-1)

      class FooAttr
        attr_accessor :bar
      end

      class BarAttr
        attr_accessor :bar, :baz
      end

      xa = true
      unless xa
        puts "hello1"
      end

      ya = false
      unless xa && ya
        puts "hello2"
      end

      za = true
      unless za
        puts "a"
        puts "b"
      else
        puts "c"
        puts "d"
      end
    RUBY
  end

  def test_endless_and_control_flow
    result = setup_group1
    assert_equal 'def d(a) =puts a;d "hello";def e(a);b=a+1;puts b;end;e 5;def b(a);if a>0;puts "positive";a;else;puts "non-positive";-a;end;end;puts b(5);puts b(-3);def a(a);if a>0;puts "positive";a;else;puts "non-positive";-a;end;end;puts a(5);puts a(-3);def c(a);if a>0;b=a*2;return b;end;0;end;puts c(3);puts c(-1);class FooAttr;attr :bar,true;end;class BarAttr;attr_accessor :bar,:baz;end;xa=!!1;puts "hello1" if !xa;ya=!1;puts "hello2" unless xa&&ya;za=!!1;if za;puts ?c;puts ?d;else;puts ?a;puts ?b;end', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 2: Method Rename Basics + Collision + Inheritance + Nested classes
  # ===========================================

  def setup_group2
    @group2 ||= minify_code(<<~RUBY)
      class Calculator
        def compute_result(x, y)
          x + y
        end

        def run_calculation
          puts compute_result(1, 2)
          puts compute_result(3, 4)
          puts compute_result(5, 6)
        end
      end
      Calculator.new.run_calculation

      class Greeter
        def initialize(name)
          @name = name
        end

        def greet_person
          puts "Hello, \#{@name}"
        end
      end
      g = Greeter.new("Alice")
      g.greet_person
      g.greet_person
      g.greet_person

      class Checker
        def is_valid?(value)
          value > 0
        end

        def check_all
          puts is_valid?(1)
          puts is_valid?(2)
          puts is_valid?(-1)
        end
      end
      Checker.new.check_all

      class Dog
        def make_sound
          "Woof"
        end
      end

      class Cat
        def make_sound
          "Meow"
        end
      end

      animals = [Dog.new, Cat.new]
      animals.each { |a| puts a.make_sound }
      animals.each { |a| puts a.make_sound }

      class Saver
        def dangerous_save!(data)
          puts data
        end
        def run
          dangerous_save!("a")
          dangerous_save!("b")
          dangerous_save!("c")
        end
      end
      Saver.new.run

      class Factory
        def self.create_instance(x)
          x * 2
        end
      end
      puts Factory.create_instance(1)
      puts Factory.create_instance(2)
      puts Factory.create_instance(3)

      class Formatter
        def to_s
          "formatter"
        end
        def long_format_method(x)
          x.to_s + to_s
        end
        def run
          puts long_format_method(1)
          puts long_format_method(2)
          puts long_format_method(3)
        end
      end
      Formatter.new.run

      class Worker
        def run
          puts internal_process("a")
          puts internal_process("b")
          puts internal_process("c")
        end

        private

        def internal_process(x)
          x + "!"
        end
      end
      Worker.new.run

      class Unused
        def long_unused_method
          42
        end
      end

      class MyServiceA
        def a
          "existing short method"
        end

        def compute_result(x)
          x * 2
        end

        def run_service
          puts a
          puts compute_result(1)
          puts compute_result(2)
          puts compute_result(3)
        end
      end
      MyServiceA.new.run_service

      class BaseClass
        def a
          "base"
        end
      end

      class ChildClass < BaseClass
        def compute_result
          a + a
        end

        def run_service
          puts compute_result
          puts compute_result
          puts compute_result
        end
      end
      ChildClass.new.run_service

      class BaseProcessor
        def long_operation(x)
          x * 2
        end
      end
      class ChildProcessor < BaseProcessor
        def long_operation(x)
          super(x) + 1
        end
      end
      puts ChildProcessor.new.long_operation(5)
      puts ChildProcessor.new.long_operation(10)
      puts ChildProcessor.new.long_operation(15)

      class Outer
        def long_method_name
          "outer"
        end
        def run
          puts long_method_name
          puts long_method_name
          puts long_method_name
        end
        class Inner
          def long_method_name
            "inner"
          end
          def run
            puts long_method_name
            puts long_method_name
            puts long_method_name
          end
        end
      end
      Outer.new.run
      Outer::Inner.new.run

      class Resolver
        def long_method_name(x)
          x * 2
        end
        def run
          a = 10
          puts long_method_name(a)
          puts long_method_name(a)
          puts long_method_name(a)
        end
      end
      Resolver.new.run
    RUBY
  end

  def test_method_rename_basics_and_collision
    result = setup_group2
    assert_equal 'class Calculator;def a(a,b) =a+b;def b;puts a(1,2);puts a(3,4);puts a(5,6);end;end;Calculator.new.b;class Greeter;def initialize(a) =@a=a;def a =puts "Hello, #{@a}";end;g=Greeter.new("Alice");g.a;g.a;g.a;class Checker;def a(a) =a>0;def b;puts a(1);puts a(2);puts a(-1);end;end;Checker.new.b;class Dog;def a ="Woof";end;class Cat;def a ="Meow";end;animals=[Dog.new,Cat.new];animals.each{puts _1.a};animals.each{puts _1.a};class Saver;def a(a) =puts a;def b;a ?a;a ?b;a ?c;end;end;Saver.new.b;class Factory;def self.a(a) =a*2;end;puts Factory.a(1);puts Factory.a(2);puts Factory.a(3);class Formatter;def to_s ="formatter";def a(a) =a.to_s+to_s;def b;puts a(1);puts a(2);puts a(3);end;end;Formatter.new.b;class Worker;def b;puts a(?a);puts a(?b);puts a(?c);end;private;def a(a) =a+"!";end;Worker.new.b;class Unused;def long_unused_method =42;end;class MyServiceA;def a ="existing short method";def b(a) =a*2;def c;puts a;puts b(1);puts b(2);puts b(3);end;end;MyServiceA.new.c;class BaseClass;def a ="base";end;class ChildClass<BaseClass;def b =a+a;def c;puts b;puts b;puts b;end;end;ChildClass.new.c;class BaseProcessor;def a(a) =a*2;end;class ChildProcessor<BaseProcessor;def a(a) =super+1;end;puts ChildProcessor.new.a(5);puts ChildProcessor.new.a(10);puts ChildProcessor.new.a(15);class Outer;def a ="outer";def b;puts a;puts a;puts a;end;class Inner;def a ="inner";def b;puts a;puts a;puts a;end;end;end;Outer.new.b;Outer::Inner.new.b;class Resolver;def b(a) =a*2;def a;a=10;puts b(a);puts b(a);puts b(a);end;end;Resolver.new.a', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 3: alias/undef Safety + Dynamic Dispatch Safety + visibility
  # ===========================================

  def setup_group3
    @group3 ||= minify_code(<<~RUBY)
      class MyService1
        def original_method
          "original"
        end
        alias new_method original_method

        def run_service
          puts original_method
          puts new_method
          puts original_method
        end
      end
      MyService1.new.run_service

      class MyService2
        def removable_method
          "removed"
        end

        def keep_method
          "kept"
        end
        undef removable_method

        def run_service
          puts keep_method
          puts keep_method
          puts keep_method
        end
      end
      MyService2.new.run_service

      class AliasDemo
        def bar; 1; end
        alias baz bar
      end
      puts AliasDemo.new.baz

      class UndefDemo
        def bar; 1; end
        def baz; 2; end
        undef bar, baz
      end

      class ProtectedService
        def assign_properties
          "assigned"
        end
        protected :assign_properties

        def call_it
          puts assign_properties
          puts assign_properties
          puts assign_properties
        end
      end
      ProtectedService.new.call_it

      class PrivateService
        def secret_method
          "secret"
        end
        private :secret_method

        def call_it
          puts secret_method
          puts secret_method
          puts secret_method
        end
      end
      PrivateService.new.call_it

      class ModuleFuncService
        def utility_method
          "utility"
        end
        module_function :utility_method

        def call_it
          puts utility_method
          puts utility_method
          puts utility_method
        end
      end
      ModuleFuncService.new.call_it

      class SendService
        def compute_result
          42
        end

        def run_service
          puts compute_result
          puts compute_result
          puts compute_result
          puts send(:compute_result)
        end
      end
      SendService.new.run_service

      class MethodRefService
        def compute_result
          42
        end

        def run_service
          puts compute_result
          puts compute_result
          m = method(:compute_result)
          puts m.call
        end
      end
      MethodRefService.new.run_service

      class PublicSendService
        def compute_result
          42
        end

        def run_service
          puts compute_result
          puts compute_result
          puts public_send(:compute_result)
        end
      end
      PublicSendService.new.run_service

      class DefMethodService
        define_method(:compute_result) { 42 }
        def run_service
          puts compute_result
          puts compute_result
          puts compute_result
        end
      end
      DefMethodService.new.run_service

      class InstMethodService
        def compute_result
          42
        end
        def run_service
          puts compute_result
          puts compute_result
          m = self.class.instance_method(:compute_result)
          puts m.bind_call(self)
        end
      end
      InstMethodService.new.run_service

      class UnderSendService
        def compute_result
          42
        end
        def run_service
          puts compute_result
          puts compute_result
          puts __send__(:compute_result)
        end
      end
      UnderSendService.new.run_service
    RUBY
  end

  def test_alias_undef_and_dynamic_dispatch_safety
    result = setup_group3
    assert_equal 'class MyService1;def original_method ="original";alias new_method original_method;def a;puts original_method;puts new_method;puts original_method;end;end;MyService1.new.a;class MyService2;def removable_method ="removed";def a ="kept";undef removable_method;def b;puts a;puts a;puts a;end;end;MyService2.new.b;class AliasDemo;def bar =1;alias baz bar;end;puts AliasDemo.new.baz;class UndefDemo;def bar =1;def baz =2;undef bar,baz;end;class ProtectedService;def assign_properties ="assigned";protected :assign_properties;def a;puts assign_properties;puts assign_properties;puts assign_properties;end;end;ProtectedService.new.a;class PrivateService;def secret_method ="secret";private :secret_method;def a;puts secret_method;puts secret_method;puts secret_method;end;end;PrivateService.new.a;class ModuleFuncService;def utility_method ="utility";module_function :utility_method;def a;puts utility_method;puts utility_method;puts utility_method;end;end;ModuleFuncService.new.a;class SendService;def compute_result =42;def a;puts compute_result;puts compute_result;puts compute_result;puts send(:compute_result);end;end;SendService.new.a;class MethodRefService;def compute_result =42;def a;puts compute_result;puts compute_result;a=method :compute_result;puts a.call;end;end;MethodRefService.new.a;class PublicSendService;def compute_result =42;def a;puts compute_result;puts compute_result;puts compute_result;end;end;PublicSendService.new.a;class DefMethodService;define_method(:compute_result){42};def a;puts compute_result;puts compute_result;puts compute_result;end;end;DefMethodService.new.a;class InstMethodService;def compute_result =42;def a;puts compute_result;puts compute_result;a=self.class.instance_method(:compute_result);puts a.bind_call(self);end;end;InstMethodService.new.a;class UnderSendService;def compute_result =42;def a;puts compute_result;puts compute_result;puts __send__(:compute_result);end;end;UnderSendService.new.a', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 4: Dead Code Elimination
  # ===========================================

  def test_dead_code_elimination
    result = minify_code(<<~RUBY)
      def compute(x)
        return x * 2
        puts "this is dead code"
        x + 1
      end
      puts compute(5)

      result_break = []
      [1, 2, 3].each do |x|
        result_break << x
        break
        result_break << x * 10
      end
      puts result_break.inspect

      result_next = []
      [1, 2, 3].each do |x|
        result_next << x
        next
        result_next << x * 100
      end
      puts result_next.inspect

      def fail_method
        raise "error"
        puts "unreachable"
      end
      begin
        fail_method
      rescue => e
        puts e.message
      end

      def compute2(x)
        if x > 0
          return x
        end
        puts "reachable"
        -x
      end
      puts compute2(5)
      puts compute2(-3)

      puts "before"
      return
      puts "after"
    RUBY
    assert_equal 'def c(a) =return a*2;puts c(5);result_break=[];[1,2,3].each{result_break<<_1;break};puts result_break.inspect;result_next=[];[1,2,3].each{result_next<<_1;next};puts result_next.inspect;def b =raise "error";begin;b;rescue=>e;puts e.message;end;def a(a);return a if a>0;puts "reachable";-a;end;puts a(5);puts a(-3);puts "before";return', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 5: Inline RBS improves method resolution
  # ===========================================

  def test_inline_rbs_improves_method_resolution
    result = minify_code(<<~RUBY)
      class Consumer
        def long_method_name(x)
          x * 2
        end
      end

      class Producer
        #: () -> Consumer
        def create_consumer
          Consumer.new
        end
      end

      p = Producer.new
      c = p.create_consumer
      puts c.long_method_name(1)
      puts c.long_method_name(2)
      puts c.long_method_name(3)
    RUBY
    assert_equal 'class Consumer;def a(a) =a*2;end;class Producer;def a =Consumer.new;end;p=Producer.new;c=p.a;puts c.a(1);puts c.a(2);puts c.a(3)', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # Group 6: RBS file improves ivar method resolution
  # ===========================================

  def test_rbs_file_improves_ivar_method_resolution
    code = <<~RUBY
      class Processor
        def long_method_name(x)
          x * 2
        end
      end

      class App
        def run
          puts @proc.long_method_name(1)
          puts @proc.long_method_name(2)
          puts @proc.long_method_name(3)
        end
      end
    RUBY

    rbs = { "(test.rbs)" => <<~RBS }
      class App
        @proc: Processor
      end
    RBS

    result = minify_code(code, rbs_files: rbs)
    assert_equal 'class Processor;def a(a) =a*2;end;class App;def run;puts @a.a(1);puts @a.a(2);puts @a.a(3);end;end', result.code
    assert_equal '', result.aliases
  end
end

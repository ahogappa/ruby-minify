# frozen_string_literal: true

require_relative 'test_helper'

class TestMetaprogramming < Minitest::Test
  include MinifyTestHelper

  # ===========================================
  # Group 1: eval variants + method_missing + lifecycle hooks + normal methods
  # ===========================================

  def setup_group1
    @group1 ||= minify_code(<<~RUBY)
      class EvalVariants
        def with_instance_eval(target_object, expression)
          result_value = target_object.instance_eval(expression)
          result_value
        end

        def with_class_eval(target_class, method_body)
          target_class.class_eval(method_body)
          target_class
        end

        def with_module_eval(target_module, code_string)
          target_module.module_eval(code_string)
          target_module
        end

        def safe_computation(input_value)
          computed_result = input_value * 2
          computed_result + 1
        end
      end

      obj = EvalVariants.new
      puts obj.with_instance_eval(42, "self * 3")
      klass = Class.new
      obj.with_class_eval(klass, "def greet; 'hi'; end")
      puts klass.new.greet
      mod = Module.new
      obj.with_module_eval(mod, "def self.hello; 42; end")
      puts mod.hello
      puts obj.safe_computation(5)
      puts obj.safe_computation(10)
      puts obj.safe_computation(15)

      class GhostMethod
        def method_missing(method_name, *arguments)
          if method_name.to_s.start_with?("say_")
            word = method_name.to_s.delete_prefix("say_")
            puts "\#{word}: \#{arguments.first}"
          else
            super
          end
        end

        def respond_to_missing?(method_name, include_private = false)
          method_name.to_s.start_with?("say_") || super
        end

        def normal_method(input_value)
          computed = input_value.to_s.upcase
          computed
        end
      end

      ghost = GhostMethod.new
      ghost.say_hello("world")
      ghost.say_goodbye("world")
      puts ghost.respond_to?(:say_hello)
      puts ghost.normal_method("test")
      puts ghost.normal_method("data")
      puts ghost.normal_method("info")

      $hook_log = []

      class BaseTracker
        def self.inherited(subclass)
          $hook_log << "inherited"
        end

        def compute_value(input_data)
          input_data * 2
        end
      end

      module TrackInclude
        def self.included(base_class)
          $hook_log << "included"
        end
      end

      module TrackExtend
        def self.extended(base_object)
          $hook_log << "extended"
        end
      end

      module TrackPrepend
        def self.prepended(base_class)
          $hook_log << "prepended"
        end
      end

      class ChildTracker < BaseTracker
        include TrackInclude
        extend TrackExtend
        prepend TrackPrepend
      end

      puts $hook_log.sort.join(",")
      obj_ct = ChildTracker.new
      puts obj_ct.compute_value(10)
      puts obj_ct.compute_value(20)
      puts obj_ct.compute_value(30)
    RUBY
  end

  def test_eval_variants_disable_variable_mangling
    result = setup_group1
    assert_equal true, result.code.include?("target_object")
    assert_equal true, result.code.include?("instance_eval")
    assert_equal true, result.code.include?("class_eval")
    assert_equal true, result.code.include?("module_eval")
  end

  def test_method_missing_respond_to_missing_preserved
    result = setup_group1
    assert_equal true, result.code.include?("method_missing")
    assert_equal true, result.code.include?("respond_to_missing?")
  end

  def test_lifecycle_hooks_preserved
    result = setup_group1
    assert_equal true, result.code.include?("inherited")
    assert_equal true, result.code.include?("included")
    assert_equal true, result.code.include?("extended")
    assert_equal true, result.code.include?("prepended")
  end

  def test_safe_method_renamed
    result = setup_group1
    # safe_computation has no eval → should be renamed
    assert_equal false, result.code.include?("safe_computation")
    # normal_method has no eval → should be renamed
    assert_equal false, result.code.include?("normal_method")
    # compute_value should be renamed
    assert_equal false, result.code.include?("compute_value")
  end

  # ===========================================
  # Group 2: Struct.new + Class.new + Combined DSL
  # ===========================================

  def setup_group2
    @group2 ||= minify_code(<<~RUBY)
      Point = Struct.new(:x, :y) do
        def distance_from_origin
          Math.sqrt(x * x + y * y)
        end
      end

      p1 = Point.new(3, 4)
      puts p1.x
      puts p1.y
      puts p1.distance_from_origin.round
      puts p1.distance_from_origin.round
      puts p1.distance_from_origin.round

      DynamicGreeter = Class.new do
        define_method(:greet_person) do |name|
          "Hello, \#{name}!"
        end

        def run_greeting(target_name)
          puts greet_person(target_name)
          puts greet_person(target_name)
          puts greet_person(target_name)
        end
      end

      DynamicGreeter.new.run_greeting("Alice")

      module Registerable
        def self.included(base_class)
          base_class.extend(ClassMethods)
        end

        module ClassMethods
          def register_item(item_name)
            @registry ||= []
            @registry << item_name
          end

          def registered_items
            @registry
          end
        end
      end

      class ServiceRegistry
        include Registerable

        register_item("auth")
        register_item("cache")
        register_item("logger")

        def process_request(request_data)
          result = request_data.upcase
          result
        end
      end

      puts ServiceRegistry.registered_items.join(",")
      svc = ServiceRegistry.new
      puts svc.process_request("hello")
      puts svc.process_request("world")
      puts svc.process_request("test")
    RUBY
  end

  def test_struct_and_dynamic_class
    result = setup_group2
    assert_equal true, result.code.include?("Struct.new")
    assert_equal true, result.code.include?("Class.new")
    assert_equal true, result.code.include?("define_method")
  end

  def test_combined_heavy_metaprogramming
    result = setup_group2
    assert_equal true, result.code.include?("include Registerable")
    assert_equal false, result.code.include?("process_request")
  end
end

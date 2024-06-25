# frozen_string_literal: true

# Shared test fixtures for rename-related tests.
# One large code block is minified once per level, then shared across test files.
# This avoids redundant TypeProf initializations (~0.32s each).

require_relative 'test_helper'

module RenameTestFixtures
  # A single code block covering all rename features:
  # - Constant aliasing (MyConstClass, modules, value constants)
  # - Method renaming (basic, singleton, collision, polymorphic, bang, question mark)
  # - Keyword argument renaming (required, optional, multiple call sites, hash shorthand)
  # - Local variable renaming
  # - Instance variable renaming (basic, attr_reader, attr_accessor, compound assignment)
  # - Class variable renaming (basic, compound, inheritance)
  # - Global variable renaming
  # - Block parameters
  # - For loops
  # - Rescue variables
  # - Compound assignment (+=, ||=, &&=)
  # - Endless method
  # - Metaprogramming safety (send, method_missing preserved)
  # - alias/undef safety
  # - Dead code elimination
  # - Dynamic dispatch exclusion
  RENAME_TEST_CODE = <<~'RUBY'
    # === Constant aliasing ===
    module ConstModule
      class ConstInner
        def cval; 42; end
      end
    end
    obj_ci = ConstModule::ConstInner.new
    puts obj_ci.cval

    MAX_RETRIES = 5
    puts MAX_RETRIES

    # === Method renaming ===
    class MethodCalc
      def compute_result(x, y)
        x + y
      end
      def run_calculation
        puts compute_result(1, 2)
        puts compute_result(3, 4)
        puts compute_result(5, 6)
      end
    end
    MethodCalc.new.run_calculation

    class MethodSingleton
      def self.create_instance(x)
        x * 2
      end
    end
    puts MethodSingleton.create_instance(1)
    puts MethodSingleton.create_instance(2)
    puts MethodSingleton.create_instance(3)

    class MethodBang
      def dangerous_save!(data)
        puts data
      end
      def run
        dangerous_save!("a")
        dangerous_save!("b")
        dangerous_save!("c")
      end
    end
    MethodBang.new.run

    class MethodQuestion
      def is_valid?(value)
        value > 0
      end
      def check_all
        puts is_valid?(1)
        puts is_valid?(-1)
        puts is_valid?(0)
      end
    end
    MethodQuestion.new.check_all

    # === Keyword argument renaming ===
    def kw_required(name:)
      name
    end
    kw_required(name: 1)

    def kw_multi(argument:)
      argument
    end
    kw_multi(argument: 1)
    kw_multi(argument: 2)
    kw_multi(argument: 3)

    def kw_optional(greeting: "hello")
      greeting
    end
    kw_optional(greeting: "world")

    def kw_default_ref(name:, other: name)
      [name, other]
    end
    kw_default_ref(name: "x")

    # === Local variable renaming ===
    def local_calc(x, y)
      result_val = x + y
      result_val * 2
    end
    puts local_calc(3, 4)

    # === Instance variable renaming ===
    class IvarBasic
      def initialize(value)
        @long_name = value
      end
      def get_value
        @long_name
      end
    end
    puts IvarBasic.new(42).get_value

    class IvarCompound
      def initialize
        @count = 0
      end
      def increment
        @count += 1
        @count
      end
    end
    ic = IvarCompound.new
    puts ic.increment
    puts ic.increment

    class IvarAttrReader
      attr_reader :very_long_name
      def initialize(x)
        @very_long_name = x
      end
    end
    puts IvarAttrReader.new(42).very_long_name

    class IvarAttrAccessor
      attr_accessor :very_long_name
      def initialize(x)
        @very_long_name = x
      end
    end
    ib = IvarAttrAccessor.new(1)
    ib.very_long_name = 42
    ib.very_long_name += 1
    puts ib.very_long_name

    # === Class variable renaming ===
    class CvarCounter
      @@total_count = 0
      def self.cvar_increment
        @@total_count += 1
        @@total_count
      end
    end
    puts CvarCounter.cvar_increment
    puts CvarCounter.cvar_increment

    # === Global variable renaming ===
    $global_name = "hello"
    puts $global_name

    $accumulator = 0
    $accumulator += 10
    puts $accumulator

    # === Block parameters ===
    [1, 2, 3].each do |item|
      puts item
    end

    # === For loop ===
    for loop_item in [4, 5, 6]
      puts loop_item
    end

    # === Rescue variable ===
    begin
      raise "error"
    rescue => error_var
      puts error_var.message
    end

    # === Compound assignment ===
    compound_x = 1
    compound_x += 2
    compound_x ||= 3
    compound_x &&= 4
    puts compound_x

    # === Endless method ===
    def endless_greet(person_name) = puts person_name
    endless_greet("hello")

    # === Metaprogramming safety ===
    class MetaSend
      def compute_result
        42
      end
      def run_meta
        puts compute_result
        puts compute_result
        puts send(:compute_result)
      end
    end
    MetaSend.new.run_meta

    class MetaMissing
      def method_missing(method_name, *arguments)
        if method_name.to_s.start_with?("say_")
          puts method_name.to_s.delete_prefix("say_")
        else
          super
        end
      end
      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s.start_with?("say_") || super
      end
      def normal_method(input_value)
        input_value.to_s.upcase
      end
    end
    mm = MetaMissing.new
    mm.say_hello
    puts mm.normal_method("test")
    puts mm.normal_method("data")
    puts mm.normal_method("info")

    # === Alias/undef safety ===
    class AliasService
      def original_method
        "original"
      end
      alias new_method original_method
      def run_alias
        puts original_method
        puts new_method
        puts original_method
      end
    end
    AliasService.new.run_alias

    class UndefService
      def removable_method
        "removed"
      end
      def keep_method
        "kept"
      end
      undef removable_method
      def run_undef
        puts keep_method
        puts keep_method
        puts keep_method
      end
    end
    UndefService.new.run_undef

    # === Dead code elimination ===
    def dead_code_fn(x)
      return x * 2
      puts "dead"
    end
    puts dead_code_fn(5)

    # === Hash shorthand ===
    def hash_short_fn(name_val, age_val)
      { name_val: name_val, age_val: age_val }
    end
    puts hash_short_fn("Alice", 30).inspect

    # === attr_accessor single (→attr :x, true) ===
    class AttrSingle
      attr_accessor :bar_prop
    end

    # === Inheritance (cvar sharing) ===
    class CvarParent
      @@shared_value = 0
      def self.cvar_write(val)
        @@shared_value = val
      end
    end
    class CvarChild < CvarParent
      def self.cvar_read
        @@shared_value
      end
    end
    CvarParent.cvar_write(42)
    puts CvarChild.cvar_read

    # === Super with keywords ===
    class SuperParent
      def kw_method(name:)
        name
      end
    end
    class SuperChild < SuperParent
      def kw_method(name:)
        super
      end
    end
    puts SuperChild.new.kw_method(name: "x")
  RUBY

  def rename_results
    @@rename_results ||= {}
  end

  def rename_result_at(level)
    rename_results[level] ||= minify_at_level(RenameTestFixtures::RENAME_TEST_CODE, level)
  end
end

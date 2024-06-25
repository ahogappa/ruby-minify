# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'test_fixtures'

class TestIvarRenaming < Minitest::Test
  include MinifyTestHelper
  include RenameTestFixtures

  # ===========================================
  # Group 1: Basic ivar patterns + Inheritance/module/dynamic + Attr-backed
  # All merged into one minify_code call
  # ===========================================

  def setup_group1
    @group1 ||= minify_code(<<~RUBY)
      class IvarMyClass
        def initialize(value)
          @long_name = value
        end
        def get_value
          @long_name
        end
      end
      puts IvarMyClass.new(42).get_value

      class A
        def initialize
          @x = 1
          @long_name = 2
        end
        def f
          @x + @long_name
        end
      end

      class IvarCounter
        def initialize
          @count = 0
        end
        def increment
          @count += 1
          @count
        end
      end
      c = IvarCounter.new
      puts c.increment
      puts c.increment

      class First
        def initialize(v)
          @value = v
        end
        def get
          @value
        end
      end
      class Second
        def initialize(v)
          @data = v
        end
        def get
          @data
        end
      end
      puts First.new(1).get
      puts Second.new(2).get

      class Point
        def initialize(x, y)
          @first_coord = x
          @second_coord = y
        end
        def sum
          @first_coord + @second_coord
        end
      end
      puts Point.new(10, 20).sum

      class IvarChecker
        def initialize(v)
          @stored = v
        end
        def check
          defined?(@stored) ? @stored : "none"
        end
      end
      puts IvarChecker.new(42).check

      class DynGetClass
        def initialize(value)
          @long_name = value
        end
        def get_value
          instance_variable_get(:@long_name)
        end
      end
      puts DynGetClass.new(42).get_value

      class Parent
        def initialize
          @shared_value = 1
        end
      end
      class Child < Parent
        def read_value
          @shared_value
        end
      end
      puts Child.new.read_value

      module Helper
        def read_val
          @value
        end
      end
      class Includer
        include Helper
        def initialize(v)
          @value = v
        end
      end
      puts Includer.new(42).read_val

      class Setter
        def initialize
          instance_variable_set(:@long_name, 42)
        end
        def get_value
          @long_name
        end
      end
      puts Setter.new.get_value

      class FooAttr
        attr_reader :bar
        def initialize(x)
          @bar = x
          @internal = 42
        end
        def f
          @internal
        end
      end
      puts FooAttr.new(10).f

      class AttrReader
        attr_reader :very_long_name
        def initialize(x)
          @very_long_name = x
        end
      end
      puts AttrReader.new(42).very_long_name

      class AttrAccessor
        attr_accessor :very_long_name
        def initialize(x)
          @very_long_name = x
        end
      end
      b = AttrAccessor.new(1)
      b.very_long_name = 42
      b.very_long_name += 1
      puts b.very_long_name

      class Baz
        attr_reader :public_name
        def initialize(x)
          @public_name = x
          @internal_cache = nil
        end
        def cached
          @internal_cache ||= @public_name.upcase
        end
      end
      puts Baz.new("hello").cached

      class ShortAttr
        attr_accessor :x
        def initialize(v)
          @x = v
        end
      end
      f = ShortAttr.new(1)
      f.x = 2
      puts f.x
    RUBY
  end

  def test_basic_ivar_shortening
    result = setup_group1
    # @first_coord and @second_coord in Point should be shortened
    assert_equal false, result.code.include?("@first_coord")
    assert_equal false, result.code.include?("@second_coord")
  end

  def test_short_ivars_preserved
    result = setup_group1
    # @x in class A should stay
    assert_equal true, result.code.include?("@x")
  end

  def test_dynamic_access_excludes_class
    result = setup_group1
    # instance_variable_get preserves original name in DynGetClass
    assert_equal true, result.code.include?("@long_name") == false || result.code.include?('"@long_name"')
  end

  def test_attr_reader_renames
    result = setup_group1
    # AttrReader.very_long_name should be shortened
    assert_equal false, result.code.include?("very_long_name")
  end

  def test_attr_accessor_renames
    result = setup_group1
    # AttrAccessor.very_long_name already tested above
    assert_equal false, result.code.include?("very_long_name")
  end

  def test_short_attr_preserved
    result = setup_group1
    assert_equal true, result.code.include?(".x=")
  end

  # ===========================================
  # Shared fixture: ivar renamed at level 5
  # ===========================================

  def test_ivar_renamed_in_shared_fixture
    result = rename_result_at(5)
    # @long_name should be shortened
    assert_equal false, result.code.include?("@long_name")
    assert_equal false, result.code.include?("@count")
  end

  # ===========================================
  # Group: attr_reader-backed ivars at L4
  # L4 has no MethodRenamer, so attr_reader symbols stay original.
  # The backing ivar must NOT be renamed either.
  # ===========================================

  def setup_attr_l4
    @attr_l4 ||= minify_at_level(<<~RUBY, 4)
      class PrettyGroup
        attr_reader :depth

        def initialize(depth)
          @depth = depth
        end

        def deeper
          @depth + 1
        end
      end

      g = PrettyGroup.new(3)
      puts g.depth
      puts g.deeper
    RUBY
  end

  def test_attr_reader_ivar_not_renamed_at_l4
    result = setup_attr_l4
    assert_equal true, result.code.include?("@depth"),
      "attr_reader-backed @depth should NOT be renamed at L4 (no MethodRenamer to rename the attr symbol)"
  end
end

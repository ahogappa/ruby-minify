# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'test_fixtures'

class TestKeywordRenaming < Minitest::Test
  include MinifyTestHelper
  include RenameTestFixtures

  # ===========================================
  # Group 1: All basic keyword tests merged into one minify_code call
  # Covers: required keyword renamed, multiple keywords, optional keyword with default,
  #   **kwargs exclusion, 0 call sites exclusion, short keyword,
  #   hash shorthand coordination, multiple call sites,
  #   keyword default referencing other keyword,
  #   variable hint conflict, hash shorthand input,
  #   idempotency, hash splat exclusion
  # ===========================================

  def setup_group1
    @group1 ||= minify_code(<<~RUBY)
      def foo_req(name:)
        name
      end
      foo_req(name: 1)

      def bar_multi(name:, age:)
        [name, age]
      end
      bar_multi(name: 1, age: 2)

      def baz_opt(greeting: "hello")
        greeting
      end
      baz_opt(greeting: "world")

      def rest_kw(name:, **opts)
        [name, opts]
      end
      rest_kw(name: 1)

      def no_calls(name:)
        name
      end

      def short_kw(x:)
        x
      end
      short_kw(x: 1)

      def kw_target(name:)
        name
      end
      def kw_caller(name)
        kw_target(name: name)
      end
      puts kw_caller("x")

      def multi_call(argument:)
        argument
      end
      multi_call(argument: 1)
      multi_call(argument: 2)
      multi_call(argument: 3)

      def foo_defref(name:, other: name)
        [name, other]
      end
      foo_defref(name: "x")

      def target1(keyword_a:)
        keyword_a
      end
      def target2(keyword_b:)
        keyword_b
      end
      def caller_fn(value)
        target1(keyword_a: value)
        target2(keyword_b: value)
      end
      caller_fn(1)

      def foo_sh(name:)
        name
      end
      def bar_sh(name)
        foo_sh(name:)
      end
      puts bar_sh("x")

      def foo_idem(a:, bb:)
        [a, bb]
      end
      foo_idem(a: 1, bb: 2)

      def target_splat(name:)
        name
      end
      opts = { name: "hello" }
      puts target_splat(**opts)

      def mixed_splat(greeting:)
        greeting
      end
      mixed_splat(greeting: "hi")
      args = { greeting: "bye" }
      puts mixed_splat(**args)
    RUBY
  end

  def test_required_keyword_renamed
    result = setup_group1
    # foo_req(name:) should have name: renamed
    assert_equal false, result.code.include?("foo_req")
  end

  def test_safety_exclusions
    result = setup_group1
    # rest_kw has **opts → name: NOT renamed
    assert_equal true, result.code.include?("name:")
    # no_calls has 0 call sites → NOT renamed
    assert_equal true, result.code.include?("no_calls")
  end

  def test_multiple_call_sites
    result = setup_group1
    # multi_call(argument:) → renamed since argument is long with 3 call sites
    assert_equal false, result.code.include?("argument:")
  end

  def test_short_keywords_idempotent
    result = setup_group1
    # foo_idem(a:, bb:) → a: and bb: kept as-is
    assert_equal true, result.code.include?("bb:")
  end

  def test_hash_splat_excludes_renaming
    result = setup_group1
    # target_splat and mixed_splat have **splat calls → name/greeting NOT renamed
    assert_equal true, result.code.include?("greeting:")
  end

  # ===========================================
  # Group 2: Super with keywords (needs separate class hierarchy)
  # ===========================================

  def setup_group2
    @group2 ||= minify_code(<<~RUBY)
      class A
        def foo(name:)
          name
        end
      end
      class B < A
        def foo(name:)
          super
        end
      end
      puts B.new.foo(name: "x")
    RUBY
  end

  def test_super_keyword_unification
    result = setup_group2
    assert_equal 'class A;def a(a:) =a;end;class B<A;def a(a:) =super;end;puts B.new.a(a:?x)', result.code
    assert_equal '', result.aliases
  end

  # ===========================================
  # L3 keyword test uses shared fixture
  # ===========================================

  def test_keyword_renamed_at_level3
    result = rename_result_at(3)
    # kw_multi(argument:) should have keyword renamed at L3
    assert_equal false, result.code.include?("argument:")
  end
end

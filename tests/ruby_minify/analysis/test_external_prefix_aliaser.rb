# frozen_string_literal: true

require_relative '../../test_helper'

class TestExternalPrefixAliaser < Minitest::Test
  def setup
    @user_paths = Set.new([[:MyApp], [:MyApp, :Config]])
  end

  def test_ignores_user_defined_paths
    aliaser = RubyMinify::ExternalPrefixAliaser.new(@user_paths)
    aliaser.collect_reference([:MyApp, :Config])
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_empty aliaser.mappings
  end

  def test_ignores_single_element_paths
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    aliaser.collect_reference([:Foo])
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_empty aliaser.mappings
  end

  def test_collects_prefix_from_full_path
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    # TypeProf::Core::AST::CallNode → prefix [:TypeProf, :Core, :AST]
    20.times { aliaser.collect_reference([:TypeProf, :Core, :AST, :CallNode]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_equal "a", aliaser.short_name_for_prefix([:TypeProf, :Core, :AST, :CallNode])
  end

  def test_below_savings_threshold_not_aliased
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    # Short prefix "A::B" (4 chars), savings_per_use = 3, declaration_cost = 1+1+4+1 = 7
    # net = 3*count - 7; need count >= 6 for net >= 10+
    # With count=2: net = 6-7 = -1 → not aliased
    2.times { aliaser.collect_reference([:A, :B, :C]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_nil aliaser.short_name_for_prefix([:A, :B, :C])
  end

  def test_short_name_for_prefix
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    20.times { aliaser.collect_reference([:TypeProf, :Core, :AST, :CallNode]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    short = aliaser.short_name_for_prefix([:TypeProf, :Core, :AST, :CallNode])
    assert_equal "a", short
  end

  def test_short_name_for_unaliased_prefix_returns_nil
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_nil aliaser.short_name_for_prefix([:Foo, :Bar])
  end

  def test_short_name_for_nil_returns_nil
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_nil aliaser.short_name_for_prefix(nil)
  end

  def test_short_name_for_single_element_returns_nil
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_nil aliaser.short_name_for_prefix([:Foo])
  end

  def test_finalized_state
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    refute aliaser.finalized?
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert aliaser.finalized?
  end

  def test_double_freeze_raises
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_raises(RuntimeError) { aliaser.assign_short_names(gen) }
  end

  def test_sorted_by_savings_descending
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    # Longer prefix → more savings per use → gets earlier (shorter) name
    20.times { aliaser.collect_reference([:VeryLong, :Prefix, :Name, :X]) }
    20.times { aliaser.collect_reference([:A, :B, :X]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    long_short = aliaser.short_name_for_prefix([:VeryLong, :Prefix, :Name, :X])
    short_short = aliaser.short_name_for_prefix([:A, :B, :X])
    # Higher savings prefix gets earlier (shorter) name
    assert_equal "a", long_short
    assert_equal "b", short_short
  end

  def test_ignores_references_with_user_defined_prefix
    # If [:MyApp] is user-defined, then [:MyApp, :Foo, :Bar] should not have
    # its prefix [:MyApp, :Foo] collected as external
    user_paths = Set.new([[:MyApp], [:MyApp, :Pipeline]])
    aliaser = RubyMinify::ExternalPrefixAliaser.new(user_paths)
    20.times { aliaser.collect_reference([:MyApp, :Pipeline, :Stage]) }
    20.times { aliaser.collect_reference([:MyApp, :Config, :Setting]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    # Neither prefix should be aliased — they're inside user-defined modules
    assert_nil aliaser.short_name_for_prefix([:MyApp, :Pipeline, :Stage])
    assert_nil aliaser.short_name_for_prefix([:MyApp, :Config, :Setting])
  end

  def test_still_collects_external_with_user_defined_present
    # External references should still be collected even when user-defined paths exist
    user_paths = Set.new([[:MyApp], [:MyApp, :Config]])
    aliaser = RubyMinify::ExternalPrefixAliaser.new(user_paths)
    20.times { aliaser.collect_reference([:External, :Lib, :Class]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    assert_equal "a", aliaser.short_name_for_prefix([:External, :Lib, :Class])
  end

  def test_collision_avoidance_with_existing_names
    user_paths = Set.new([[:a]])  # 'a' is a user-defined constant name
    aliaser = RubyMinify::ExternalPrefixAliaser.new(user_paths)
    20.times { aliaser.collect_reference([:TypeProf, :Core, :AST, :CallNode]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    short = aliaser.short_name_for_prefix([:TypeProf, :Core, :AST, :CallNode])
    # Should skip "a" (collision) and use "b"
    assert_equal "b", short
  end

  def test_generate_prefix_declarations
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    20.times { aliaser.collect_reference([:TypeProf, :Core, :AST, :CallNode]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    decls = aliaser.generate_prefix_declarations
    assert_equal ["a=TypeProf::Core::AST"], decls
  end

  def test_chained_declarations
    aliaser = RubyMinify::ExternalPrefixAliaser.new(Set.new)
    # Two nested prefixes: TypeProf::Core and TypeProf::Core::AST
    20.times { aliaser.collect_reference([:TypeProf, :Core, :Something]) }
    20.times { aliaser.collect_reference([:TypeProf, :Core, :AST, :CallNode]) }
    gen = RubyMinify::NameGenerator.new([], prefix: '')
    aliaser.assign_short_names(gen)
    decls = aliaser.generate_prefix_declarations
    # Shorter prefix declared first, longer prefix chains through shorter alias
    assert_equal ["b=TypeProf::Core", "a=b::AST"], decls
  end
end

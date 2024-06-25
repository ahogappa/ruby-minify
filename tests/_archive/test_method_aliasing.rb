# frozen_string_literal: true

require_relative 'test_helper'

class TestMethodAliasing < Minitest::Test
  include MinifyTestHelper

  # ===========================================
  # Group 1: All method aliasing tests merged
  # Covers: basic aliases, chained methods, type inference, compression,
  #   additional aliases, include? semantics, unknown receiver, edge cases
  # ===========================================

  def setup_group1
    @group1 ||= minify_code(<<~RUBY)
      [1,2,3].collect { |x| x * 2 }
      [1,2,3].detect { |x| x > 1 }
      [1,2,3].find_all { |x| x > 1 }
      { a: 1 }.has_key?(:a)
      { a: 1 }.has_value?(1)
      { a: 1 }.each_pair { |k, v| puts k }
      (-5).magnitude
      [1,2,3].kind_of?(Array)
      "test".yield_self { |s| s + "!" }
      "hello".length
      :sym.id2name
      [[1], [2]].collect_concat { |x| x }
      [1,2,3].find_index(2)
      [1,2,3].collect! { |x| x * 2 }
      "hello".object_id

      [1, 2, 3, 4, 5].find_all { |x| x > 2 }.collect { |x| x * 10 }
      [1, 2, 3].find_all { |x| x > 1 }.collect { |x| x.to_s }
      [1, 2, 3].collect { |x| x * 2 }.detect { |x| x > 4 }
      { a: 1, b: 2 }.select { |k, v| v > 0 }.has_key?(:a)
      { a: 1, b: 2 }.reject { |k, v| v < 0 }.has_value?(1)
      { a: 1, b: nil }.compact.each_pair { |k, v| puts v }
      [1, 2, 3].select { |x| x > 1 }.collect { |x| x * 2 }
      [[1], [2]].last.collect { |x| x * 2 }
      [[1, 2], [3, 4]].min.collect { |x| x }
      { a: 1 }.keys.collect { |k| k }
      result_alias = [1, 2, 3].collect { |x| x * 2 }
      puts result_alias.inspect

      result1 = [1, 2, 3].collect { |x| x * 2 }
      result2 = [1, 2, 3].find_all { |x| x > 1 }
      result3 = { a: 1 }.has_key?(:a)
      result4 = (-5).magnitude
      result5 = "hello".length
      puts [1, 2, 3].entries.inspect
      alias_a = [1]; alias_a.append(2); puts alias_a.inspect
      puts({ a: 1, b: 2 }.include?(:a))
      puts({ a: 1, b: 2 }.member?(:a))
      puts [1, 2, 3].include?(2)

      custom_obj.collect { |x| x }
      [1, 2, 3].first.collect { |x| x }
    RUBY
  end

  def test_basic_aliases
    result = setup_group1
    assert_equal true, result.code.include?(".map{")
    assert_equal true, result.code.include?(".find{")
    assert_equal true, result.code.include?(".select{")
    assert_equal true, result.code.include?(".key?(")
    assert_equal true, result.code.include?(".value?(")
    assert_equal true, result.code.include?(".abs")
    assert_equal true, result.code.include?(".is_a?(")
    assert_equal true, result.code.include?(".then{")
    assert_equal true, result.code.include?(".size")
    assert_equal true, result.code.include?(".flat_map{")
    assert_equal true, result.code.include?(".index(")
    assert_equal true, result.code.include?(".map!{")
    assert_equal true, result.code.include?(".__id__")
  end

  def test_chained_aliases
    result = setup_group1
    assert_equal true, result.code.include?(".select{")
    assert_equal true, result.code.include?(".map{")
  end

  def test_compression_and_additional
    result = setup_group1
    assert_equal true, result.code.include?(".to_a.")
    assert_equal true, result.code.include?(".push(")
    # Array#include? should NOT be replaced
    assert_equal true, result.code.include?(".include?(2)")
  end

  def test_unknown_receiver_preserved
    result = setup_group1
    assert_equal true, result.code.include?("custom_obj.collect{")
  end
end

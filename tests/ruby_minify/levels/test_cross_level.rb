# frozen_string_literal: true

require_relative 'level_test_helper'

class TestCrossLevel < Minitest::Test
  include MinifyTestHelper
  include LevelTestHelper

  def test_default_level_is_3
    assert_equal 3, RubyMinify::Minifier::DEFAULT_LEVEL
  end

  # Compression should be monotonically non-increasing across levels
  def test_monotonic_compression
    sizes = (0..5).map { |l| minify_at_level(LEVEL_TEST_CODE, l, verify_output: false).code.bytesize }
    sizes.each_cons(2) do |higher, lower|
      assert_operator higher, :>=, lower,
        "Level compression should be monotonically non-increasing: #{sizes.inspect}"
    end
  end
end

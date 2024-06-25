# frozen_string_literal: true

require_relative 'test_helper'

class TestResolveLevel < Minitest::Test
  def test_numeric_levels
    (0..5).each do |n|
      assert_equal n, RubyMinify::Minifier.resolve_level(n.to_s)
    end
  end

  def test_stable_alias_resolves_to_level_3
    assert_equal 3, RubyMinify::Minifier.resolve_level('stable')
  end

  def test_unstable_alias_resolves_to_level_4
    assert_equal 4, RubyMinify::Minifier.resolve_level('unstable')
  end

  def test_min_alias_resolves_to_level_0
    assert_equal 0, RubyMinify::Minifier.resolve_level('min')
  end

  def test_max_alias_resolves_to_level_5
    assert_equal 5, RubyMinify::Minifier.resolve_level('max')
  end

  def test_invalid_level_raises
    assert_raises(ArgumentError) { RubyMinify::Minifier.resolve_level('unknown') }
    assert_raises(ArgumentError) { RubyMinify::Minifier.resolve_level('6') }
    assert_raises(ArgumentError) { RubyMinify::Minifier.resolve_level('-1') }
  end
end

class TestCompressCLI < Minitest::Test
  MINIFY_BIN = File.expand_path('../bin/minify', __dir__)

  def setup
    @input = Tempfile.new(['test_compress', '.rb'])
    @input.write("puts 'hello world'")
    @input.flush
  end

  def teardown
    @input.close!
  end

  def test_compress_with_numeric_level
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, MINIFY_BIN, '-c', '0', @input.path)
    assert status.success?, "minify failed: #{stderr}"
  end

  def test_compress_with_stable
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, MINIFY_BIN, '-c', 'stable', @input.path)
    assert status.success?, "minify failed: #{stderr}"
  end

  def test_compress_with_unstable
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, MINIFY_BIN, '-c', 'unstable', @input.path)
    assert status.success?, "minify failed: #{stderr}"
  end

  def test_compress_long_form
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, MINIFY_BIN, '--compress', 'stable', @input.path)
    assert status.success?, "minify failed: #{stderr}"
  end

  def test_compress_invalid_value
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, MINIFY_BIN, '-c', 'invalid', @input.path)
    refute status.success?
    assert stderr.include?("Invalid compress level"), "Expected 'Invalid compress level' in stderr: #{stderr}"
  end

  def test_help_shows_compress_option
    stdout, _stderr, status = Open3.capture3(RbConfig.ruby, MINIFY_BIN, '--help')
    assert status.success?
    assert stdout.include?("--compress"), "Expected '--compress' in help output"
  end
end

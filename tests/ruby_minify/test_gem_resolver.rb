# frozen_string_literal: true

require_relative '../test_helper'

class TestGemResolver < Minitest::Test
  def setup
    @resolver = RubyMinify::GemResolver.new
  end

  def test_resolve_known_gem
    result = @resolver.call("json")
    assert_instance_of RubyMinify::GemResolver::GemResolution, result
    assert result.entry_path
    assert result.project_root
  end

  def test_entry_path_is_existing_rb_file
    result = @resolver.call("json")
    assert result.entry_path.end_with?(".rb")
    assert File.exist?(result.entry_path)
  end

  def test_project_root_is_gem_dir
    result = @resolver.call("json")
    spec = Gem::Specification.find_by_name("json")
    assert_equal spec.gem_dir, result.project_root
  end

  def test_entry_path_is_under_project_root
    result = @resolver.call("json")
    assert result.entry_path.start_with?(result.project_root)
  end

  def test_resolve_unknown_gem_raises
    assert_raises(RubyMinify::Pipeline::GemNotFoundError) do
      @resolver.call("nonexistent_gem_xyz_12345")
    end
  end

  def test_resolve_unknown_gem_error_has_gem_name
    err = assert_raises(RubyMinify::Pipeline::GemNotFoundError) do
      @resolver.call("nonexistent_gem_xyz_12345")
    end
    assert_equal "nonexistent_gem_xyz_12345", err.gem_name
  end
end

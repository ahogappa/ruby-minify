# frozen_string_literal: true

module RubyMinify
  class GemResolver
    GemResolution = Data.define(:entry_path, :project_root)

    def call(gem_name)
      spec = Gem::Specification.find_by_name(gem_name)
      entry_path = spec.full_require_paths
        .map { |dir| File.join(dir, "#{gem_name}.rb") }
        .find { |p| File.exist?(p) }
      raise Pipeline::GemNotFoundError.new(gem_name) unless entry_path

      GemResolution.new(entry_path: entry_path, project_root: spec.gem_dir)
    rescue Gem::MissingSpecError
      raise Pipeline::GemNotFoundError.new(gem_name)
    end
  end
end

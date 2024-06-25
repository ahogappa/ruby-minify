# frozen_string_literal: true

require_relative "lib/ruby_minify/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-minify"
  spec.version = RubyMinify::VERSION
  spec.authors = ["ahogappa"]
  spec.email = ["ahogappa@gmail.com"]

  spec.summary = "A Ruby source code minifier powered by TypeProf type inference"
  spec.description = "RubyMinify compresses Ruby source files by shortening identifiers, aliasing constants, and removing whitespace while preserving correctness through type-aware analysis."
  spec.homepage = "https://github.com/ahogappa0613/ruby-minify"
  spec.required_ruby_version = ">= 4.0.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ahogappa0613/ruby-minify"
  spec.metadata["changelog_uri"] = "https://github.com/ahogappa0613/ruby-minify"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["minify"]
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end

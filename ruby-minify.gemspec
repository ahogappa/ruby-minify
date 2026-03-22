# frozen_string_literal: true

require_relative "lib/ruby_minify/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-minify"
  spec.version = RubyMinify::VERSION
  spec.authors = ["ahogappa"]
  spec.email = ["ahogappa@gmail.com"]

  spec.summary = "A Ruby source code minifier with type-aware renaming"
  spec.description = "RubyMinify minifies Ruby source code using Prism AST transformations and TypeProf type inference. " \
                     "It supports multi-file bundling via require_relative, 6 compression levels (whitespace removal, " \
                     "constant folding, constant/variable/method renaming), and preserves functional equivalence " \
                     "through scope-aware analysis."
  spec.homepage = "https://github.com/ahogappa/ruby-minify"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ahogappa/ruby-minify"
  spec.metadata["changelog_uri"] = "https://github.com/ahogappa/ruby-minify/releases"

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

  spec.add_dependency "prism", ">= 1.4.0"
  spec.add_dependency "typeprof", ">= 0.31.0"
  spec.add_dependency "rubocop"
end

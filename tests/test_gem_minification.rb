# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'fileutils'
require 'rbconfig'
require_relative '../lib/ruby_minify'

# Test that minified gems pass their own test suites.
# Excluded from default `rake test` — run with `rake test:gems`.
# Requires BUNDLE_GEMFILE=Gemfile.gems_test so target gems are available.
class TestGemMinification < Minitest::Test
  GEM_TESTS_DIR = File.expand_path('../gem_tests', __dir__)

  GEMS = {
    sinatra: {
      gem_name: 'sinatra',
      test_gemfile: 'Gemfile.test',
      test_files: %w[
        sinatra/test/routing_test.rb
        sinatra/test/helpers_test.rb
        sinatra/test/settings_test.rb
        sinatra/test/filter_test.rb
        sinatra/test/request_test.rb
        sinatra/test/response_test.rb
        sinatra/test/result_test.rb
        sinatra/test/base_test.rb
        sinatra/test/delegator_test.rb
        sinatra/test/streaming_test.rb
        sinatra/test/middleware_test.rb
        sinatra/test/sinatra_test.rb
        sinatra/test/server_test.rb
        sinatra/test/static_test.rb
        sinatra/test/extensions_test.rb
        sinatra/test/mapped_error_test.rb
        sinatra/test/templates_test.rb
        sinatra/test/route_added_hook_test.rb
        sinatra/test/compile_test.rb
        sinatra/test/host_authorization_test.rb
        sinatra/test/indifferent_hash_test.rb
        sinatra/test/rack_test.rb
        sinatra/test/readme_test.rb
        sinatra/test/erb_test.rb
        sinatra/test/rdoc_test.rb
        sinatra/test/liquid_test.rb
        sinatra/test/encoding_test.rb
        sinatra/test/asciidoctor_test.rb
        sinatra/test/builder_test.rb
        sinatra/test/haml_test.rb
        sinatra/test/markaby_test.rb
        sinatra/test/markdown_test.rb
        sinatra/test/nokogiri_test.rb
        sinatra/test/rabl_test.rb
        sinatra/test/sass_test.rb
        sinatra/test/scss_test.rb
        sinatra/test/slim_test.rb
        sinatra/test/yajl_test.rb
      ],
      min_level: 3,
      max_level: 3,
    },
    rubocop: {
      gem_name: 'rubocop',
      test_file_patterns: ['rubocop/spec/rubocop/**/*_spec.rb'],
      exclude_test_patterns: %w[
        rubocop/spec/rubocop/server/**/*_spec.rb
        rubocop/spec/rubocop/cli/**/*_spec.rb
      ],
      exclude_test_files: %w[
        rubocop/spec/rubocop/cops_documentation_generator_spec.rb
        rubocop/spec/rubocop/runner_spec.rb
        rubocop/spec/rubocop/cli_spec.rb
        rubocop/spec/rubocop/lsp/server_spec.rb
        rubocop/spec/rubocop/mcp/server_spec.rb
        rubocop/spec/rubocop/runner_formatter_invocation_spec.rb
      ],
      test_runner: :rspec,
      min_level: 3,
      max_level: 3,
    }
  }.freeze

  GEMS.each do |gem_key, config|
    min_level = config[:min_level] || 0
    max_level = config[:max_level] || 5
    (min_level..max_level).each do |level|
      define_method(:"test_#{gem_key}_level#{level}") do
        gem_name = config[:gem_name]

        begin
          resolution = RubyMinify::GemResolver.new.call(gem_name)
        rescue RubyMinify::Pipeline::GemNotFoundError
          skip "#{gem_name} gem not available (use BUNDLE_GEMFILE=Gemfile.gems_test)"
        end

        test_files = resolve_test_files(config)
        skip "no test files found for #{gem_name} (clone repos into gem_tests/)" if test_files.empty?
        test_files.each { |f| skip "gem test not found: #{f}" unless File.exist?(f) }

        gem_dir = File.join(GEM_TESTS_DIR, gem_key.to_s)
        test_gemfile = config[:test_gemfile] || 'Gemfile'
        assert_minified_gem_passes(
          resolution: resolution,
          test_files: test_files,
          level: level,
          gem_name: gem_name,
          test_runner: config[:test_runner],
          gem_dir: gem_dir,
          test_gemfile: test_gemfile
        )
      end
    end
  end

  private

  def resolve_test_files(config)
    test_files = Array(config[:test_files]).map { |f| File.join(GEM_TESTS_DIR, f) }
    if config[:test_file_patterns]
      excludes = Array(config[:exclude_test_files]).map { |f| File.join(GEM_TESTS_DIR, f) }
      Array(config[:exclude_test_patterns]).each do |pat|
        excludes.concat(Dir.glob(File.join(GEM_TESTS_DIR, pat)))
      end
      config[:test_file_patterns].each do |pattern|
        test_files.concat(Dir.glob(File.join(GEM_TESTS_DIR, pattern)) - excludes)
      end
      test_files.uniq!
    end
    test_files
  end

  def assert_minified_gem_passes(resolution:, test_files:, level:, gem_name:, test_runner: nil, gem_dir: nil, test_gemfile: 'Gemfile')
    baseline_failures = baseline_failures_for(gem_name, test_files, resolution, test_runner: test_runner, gem_dir: gem_dir, test_gemfile: test_gemfile)

    minifier = RubyMinify::Minifier.new
    result = minifier.call(
      resolution.entry_path,
      level: level,
      project_root: resolution.project_root,
      gem_names: [gem_name],
      gem_require_paths: resolution.require_paths
    )

    content = result.aliases.empty? ? result.content : "#{result.content};#{result.aliases}"

    Dir.mktmpdir("minify_gem_test") do |tmpdir|
      matching_root = resolution.require_paths.detect { |p| resolution.entry_path.start_with?("#{p}/") }
      assert matching_root, "#{gem_name}: entry_path not under any require_path"
      relative = resolution.entry_path.delete_prefix("#{matching_root}/")
      minified_path = File.join(tmpdir, relative)
      FileUtils.mkdir_p(File.dirname(minified_path))
      File.write(minified_path, content)

      minified = run_gem_tests(test_files, tmpdir, test_runner: test_runner, gem_dir: gem_dir,
                               test_gemfile: test_gemfile, replace_paths: resolution.require_paths)
      minified_count = parse_test_count(minified[:stdout])
      assert minified_count,
        "#{gem_name} L#{level}: no test summary found (minified code likely crashed)\nstderr: #{minified[:stderr][0, 300]}"
      assert minified_count > 0, "#{gem_name} L#{level}: 0 tests ran"
      minified_failures = parse_test_result(minified[:stdout])
      new_failures = minified_failures - baseline_failures
      assert new_failures.empty?,
        "#{gem_name} L#{level}: #{new_failures.size} new failure(s) (not in baseline):\n#{new_failures.join("\n")}"
    end
  end

  def baseline_failures_for(gem_name, test_files, resolution, test_runner: nil, gem_dir: nil, test_gemfile: 'Gemfile')
    cache = self.class.baseline_cache
    return cache[gem_name] if cache.key?(gem_name)

    baseline = run_gem_tests(test_files, resolution.require_paths.first, test_runner: test_runner, gem_dir: gem_dir, test_gemfile: test_gemfile)
    cache[gem_name] = parse_test_result(baseline[:stdout])
  end

  def self.baseline_cache
    @baseline_cache ||= {}
  end

  def run_gem_tests(test_files, lib_dir, test_runner: nil, gem_dir: nil, test_gemfile: 'Gemfile', replace_paths: [])
    test_files = Array(test_files)
    include_args = ["-I", lib_dir]

    # Build a setup preamble that removes original gem paths and keeps lib_dir at front
    setup_code = if replace_paths.any?
      lines = replace_paths.map { |p| "$LOAD_PATH.delete(#{p.inspect})" }
      lines << "$LOAD_PATH.unshift(#{lib_dir.inspect}) unless $LOAD_PATH[0] == #{lib_dir.inspect}"
      lines.join('; ')
    end

    if test_runner == :rspec
      args = build_rspec_args(test_files, lib_dir, include_args, setup_code: setup_code)
    elsif test_files.size == 1
      if setup_code
        args = [*include_args, "-e", "#{setup_code}; load #{test_files.first.inspect}"]
      else
        args = [*include_args, test_files.first]
      end
    else
      runner = Tempfile.new(['gem_test_runner', '.rb'])
      preamble = setup_code ? "#{setup_code}\n" : ""
      runner.write(<<~RUBY)
        #{preamble}minified_lib = #{lib_dir.inspect}
        original_unshift = $LOAD_PATH.method(:unshift)
        $LOAD_PATH.define_singleton_method(:unshift) do |*args|
          original_unshift.call(*args)
          if $LOAD_PATH.index(minified_lib) != 0
            $LOAD_PATH.delete(minified_lib)
            original_unshift.call(minified_lib)
          end
          self
        end
        #{test_files.map { |f| "require #{f.inspect}" }.join("\n")}
      RUBY
      runner.flush
      args = [*include_args, runner.path]
    end
    stdout_file = Tempfile.new('gem_test_stdout')
    stderr_file = Tempfile.new('gem_test_stderr')
    stdout_file.close
    stderr_file.close
    work_dir = if gem_dir
      gem_dir
    elsif test_runner == :rspec
      find_spec_dir(test_files.first) || File.dirname(test_files.first)
    else
      File.dirname(test_files.first)
    end
    gem_gemfile = gem_dir ? File.expand_path(test_gemfile, gem_dir) : nil
    pid = Bundler.with_unbundled_env do
      env = { 'BUNDLE_GEMFILE' => gem_gemfile }
      if gem_gemfile && File.exist?(gem_gemfile)
        cmd = ['bundle', 'exec', RbConfig.ruby, *args]
      else
        cmd = [RbConfig.ruby, *args]
      end
      spawn(
        env,
        *cmd,
        chdir: work_dir,
        out: [stdout_file.path, 'w'],
        err: [stderr_file.path, 'w']
      )
    end
    timeout = test_files.size > 10 ? 600 : 120
    waiter = Thread.new { Process.wait2(pid) }
    if waiter.join(timeout)
      { stdout: File.read(stdout_file.path), stderr: File.read(stderr_file.path), status: waiter.value[1] }
    else
      Process.kill('TERM', pid)
      waiter.join
      { stdout: File.read(stdout_file.path), stderr: "TIMEOUT after #{timeout}s\n" + File.read(stderr_file.path), status: nil }
    end
  ensure
    stdout_file&.unlink
    stderr_file&.unlink
    runner&.close!
    @rspec_runner&.close!
    @rspec_runner = nil
  end

  def build_rspec_args(test_files, lib_dir, include_args, setup_code: nil)
    spec_dir = find_spec_dir(test_files.first)
    runner = Tempfile.new(['rspec_runner', '.rb'])
    preamble = setup_code ? "#{setup_code}\n" : ""
    runner.write(<<~RUBY)
      #{preamble}$LOAD_PATH.unshift(#{spec_dir.inspect}) if #{spec_dir.inspect}
      require "rspec/core"
      exit(RSpec::Core::Runner.run(#{test_files.inspect} + ["--format", "progress", "--order", "defined", "--require", "spec_helper"]))
    RUBY
    runner.flush
    @rspec_runner = runner
    [*include_args, runner.path]
  end

  def find_spec_dir(test_file)
    dir = File.dirname(test_file)
    until dir == '/' || dir == '.'
      return dir if File.basename(dir) == 'spec'
      dir = File.dirname(dir)
    end
    nil
  end

  def parse_test_count(output)
    if output =~ /(\d+) (?:runs?|tests?),/
      $1.to_i
    elsif output =~ /(\d+) examples?,/
      $1.to_i
    end
  end

  def parse_test_result(output)
    failures = []

    output.scan(/^(?:Failure|Error): (\S+)\((\S+)\)/) do |test_name, klass|
      failures << "#{klass}##{test_name}"
    end

    output.scan(/^\s+\d+\) (?:Failure|Error):\n(\S+#\S+)/) do |match|
      failures << match[0]
    end

    output.scan(/^rspec (\S+:\d+)/) do |match|
      failures << match[0]
    end

    failures.sort.uniq
  end
end

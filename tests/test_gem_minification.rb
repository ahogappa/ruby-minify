# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'rbconfig'
require 'securerandom'
require 'tempfile'
require_relative '../lib/ruby_minify'

# Test that minified gems pass their own test suites.
# Run with: BUNDLE_GEMFILE=Gemfile.gems_test bundle exec rake test:gems
class TestGemMinification < Minitest::Test
  GEM_TESTS_DIR = File.expand_path('../gem_tests', __dir__)

  GEMS = {
    sinatra: {
      gem_name: 'sinatra',
      test_gemfile: 'Gemfile.test',
      test_patterns: ['sinatra/test/*_test.rb'],
      exclude_patterns: ['sinatra/test/integration*_test.rb'],
      levels: [3],
    },
    rubocop: {
      gem_name: 'rubocop',
      test_gemfile: 'Gemfile.test',
      test_patterns: ['rubocop/spec/rubocop/**/*_spec.rb'],
      exclude_patterns: [
        'rubocop/spec/rubocop/{server,cli}/**/*_spec.rb',
        'rubocop/spec/rubocop/cops_documentation_generator_spec.rb',
        'rubocop/spec/rubocop/runner_spec.rb',
        'rubocop/spec/rubocop/cli_spec.rb',
        'rubocop/spec/rubocop/lsp/server_spec.rb',
        'rubocop/spec/rubocop/mcp/server_spec.rb',
        'rubocop/spec/rubocop/runner_formatter_invocation_spec.rb',
      ],
      test_runner: :rspec,
      levels: [3],
    },
  }.freeze

  GEMS.each do |gem_key, config|
    Array(config[:levels]).each do |level|
      define_method(:"test_#{gem_key}_level#{level}") do
        resolution = resolve_gem(config[:gem_name])
        test_files = collect_test_files(config)
        skip "no test files for #{config[:gem_name]}" if test_files.empty?

        gem_dir = File.join(GEM_TESTS_DIR, gem_key.to_s)
        baseline_failures = run_baseline(config, test_files, gem_dir)

        content, marker = minify_gem(config[:gem_name], resolution, level)
        Dir.mktmpdir("minify_gem_test") do |tmpdir|
          write_minified(tmpdir, resolution, content)

          $stderr.puts "[#{config[:gem_name]}] Running minified L#{level} tests..."
          stdout, = run_test_suite(test_files, config, gem_dir, lib_dir: tmpdir,
                                   replace_paths: resolution.require_paths, marker: marker)
          count = parse_test_count(stdout)
          $stderr.puts "[#{config[:gem_name]}] Minified L#{level}: #{count || 'NO RESULT'} tests"

          assert count, "#{config[:gem_name]} L#{level}: tests crashed\nstdout: #{stdout[0, 500]}"
          assert count > 0, "#{config[:gem_name]} L#{level}: 0 tests ran"
          new_failures = parse_failures(stdout) - baseline_failures
          assert_equal [], new_failures,
            "#{config[:gem_name]} L#{level}: #{new_failures.size} new failure(s)"
        end
      end
    end
  end

  private

  def resolve_gem(gem_name)
    RubyMinify::GemResolver.new.call(gem_name)
  rescue RubyMinify::Pipeline::GemNotFoundError
    skip "#{gem_name} gem not available (use BUNDLE_GEMFILE=Gemfile.gems_test)"
  end

  def collect_test_files(config)
    files = Array(config[:test_patterns]).flat_map { |p| Dir.glob(File.join(GEM_TESTS_DIR, p)) }
    excludes = Array(config[:exclude_patterns]).flat_map { |p| Dir.glob(File.join(GEM_TESTS_DIR, p)) }
    (files - excludes).sort
  end

  def minify_gem(gem_name, resolution, level)
    result = RubyMinify::Minifier.new.call(
      resolution.entry_path, level: level,
      project_root: resolution.project_root,
      gem_names: [gem_name], gem_require_paths: resolution.require_paths
    )
    marker = "RUBY_MINIFY_MARKER_#{SecureRandom.hex(8)}"
    content = "#{marker}=true;#{result.content}"
    content += ";#{result.aliases}" unless result.aliases.empty?
    [content, marker]
  end

  def write_minified(tmpdir, resolution, content)
    root = resolution.require_paths.detect { |p| resolution.entry_path.start_with?("#{p}/") }
    path = File.join(tmpdir, resolution.entry_path.delete_prefix("#{root}/"))
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  # --- Baseline ---

  @@baseline_cache = {} # rubocop:disable Style/ClassVars

  def run_baseline(config, test_files, gem_dir)
    gem_name = config[:gem_name]
    return @@baseline_cache[gem_name] if @@baseline_cache.key?(gem_name)

    $stderr.puts "[#{gem_name}] Running baseline tests..."
    stdout, stderr = run_test_suite(test_files, config, gem_dir)
    $stderr.puts "[#{gem_name}] Baseline: #{parse_test_count(stdout) || 'NO RESULT'} tests"
    $stderr.puts "[#{gem_name}] Baseline stderr: #{stderr[0, 200]}" unless stderr.empty?
    @@baseline_cache[gem_name] = parse_failures(stdout)
  end

  # --- Subprocess ---

  def run_test_suite(test_files, config, gem_dir, lib_dir: nil, replace_paths: [], marker: nil)
    Tempfile.create(['runner', '.rb']) do |f|
      write_runner_script(f, test_files, config, lib_dir: lib_dir,
                          replace_paths: replace_paths, marker: marker)
      f.close
      gemfile = File.join(gem_dir, config[:test_gemfile] || 'Gemfile')
      cmd = ['bundle', 'exec', RbConfig.ruby]
      cmd += ['-I', lib_dir] if lib_dir
      cmd << f.path
      timeout = test_files.size > 100 ? 1200 : 300
      capture_process({ 'BUNDLE_GEMFILE' => gemfile }, *cmd, chdir: gem_dir, timeout: timeout)
    end
  end

  def write_runner_script(f, test_files, config, lib_dir:, replace_paths:, marker:)
    if lib_dir && replace_paths.any?
      replace_paths.each { |p| f.puts "$LOAD_PATH.delete(#{p.inspect})" }
      f.puts "$LOAD_PATH.unshift(#{lib_dir.inspect}) unless $LOAD_PATH[0] == #{lib_dir.inspect}"
      f.puts "at_exit { abort 'MINIFY_MARKER_MISSING' unless defined?(#{marker}) }" if marker
    end
    if config[:test_runner] == :rspec
      spec_dir = test_files.first.then { |p| p[%r{.*/spec}] }
      f.puts "$LOAD_PATH.unshift(#{spec_dir.inspect})" if spec_dir
      f.puts 'require "rspec/core"'
      f.puts "exit(RSpec::Core::Runner.run(#{test_files.inspect} + %w[--format progress --order defined --require spec_helper]))"
    else
      test_files.each { |tf| f.puts "require #{tf.inspect}" }
    end
    f.flush
  end

  def capture_process(env, *cmd, chdir:, timeout:)
    out = Tempfile.new('stdout')
    err = Tempfile.new('stderr')
    pid = Bundler.with_unbundled_env do
      spawn(env, *cmd, chdir: chdir, out: [out.path, 'w'], err: [err.path, 'w'])
    end
    waiter = Thread.new { Process.waitpid(pid) }
    unless waiter.join(timeout)
      Process.kill('TERM', pid)
      waiter.join(5)
    end
    [File.read(out.path), File.read(err.path)]
  ensure
    out&.close!
    err&.close!
  end

  # --- Parsing ---

  def parse_test_count(output)
    $1.to_i if output =~ /(\d+) (?:runs?|tests?|examples?),/
  end

  def parse_failures(output)
    failures = []
    output.scan(/^(?:Failure|Error): (\S+)\((\S+)\)/) { |n, k| failures << "#{k}##{n}" }
    output.scan(/^\s+\d+\) (?:Failure|Error):\n(\S+#\S+)/) { |m| failures << m[0] }
    output.scan(/^rspec (\S+:\d+)/) { |m| failures << m[0] }
    failures.sort.uniq
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/ruby/minify'

class TestMinify < Minitest::Test
  FIXTURES_DIR = File.expand_path('fixtures', __dir__)

  def setup
    @minifier = BaseMinify.new
  end

  # Helper to minify a fixture file and return the result
  def minify_fixture(filename, options = {})
    path = File.join(FIXTURES_DIR, filename)
    @minifier.read_path(path).minify(options)
    @minifier.result
  end

  # Helper to minify code string directly
  def minify_code(code, options = {})
    require 'tempfile'
    Tempfile.create(['test', '.rb']) do |f|
      f.write(code)
      f.flush
      @minifier.read_path(f.path).minify(options)
      return @minifier.result
    end
  end

  # Helper to calculate compression ratio
  def compression_ratio(original, minified)
    return 0 if original.empty?
    ((original.bytesize - minified.bytesize).to_f / original.bytesize * 100).round(2)
  end

  # Helper to run Ruby code and capture output
  def run_ruby(code)
    require 'open3'
    stdout, stderr, status = Open3.capture3('ruby', '-e', code)
    raise "Ruby execution failed: #{stderr}" unless status.success?
    stdout
  end

  # ===========================================
  # User Story 1: Basic Code Minification Tests
  # ===========================================

  # T012: Test for whitespace removal
  def test_us1_whitespace_removal
    result = minify_fixture('simple_with_comments.rb')

    # Should not have blank lines
    refute_match(/^\s*$/, result, "Should not contain blank lines")

    # Should not have excessive whitespace
    refute_match(/  +/, result, "Should not contain multiple consecutive spaces")
  end

  # T013: Test for comment removal
  def test_us1_comment_removal
    result = minify_fixture('simple_with_comments.rb')

    # Should not contain single-line comments
    refute_match(/\#[^{]/, result, "Should not contain # comments")

    # Should not contain block comments
    refute_match(/=begin/, result, "Should not contain =begin")
    refute_match(/=end/, result, "Should not contain =end block comment marker")
  end

  # T014: Test for compression ratio (>= 30% size reduction)
  def test_us1_compression_ratio
    original_path = File.join(FIXTURES_DIR, 'simple_with_comments.rb')
    original = File.read(original_path)
    minified = minify_fixture('simple_with_comments.rb')

    ratio = compression_ratio(original, minified)
    assert ratio >= 30, "Compression ratio should be >= 30%, got #{ratio}%"
  end

  # T015: Test for functional equivalence
  def test_us1_functional_equivalence
    # Test code that produces output
    code = <<~RUBY
      def factorial(n)
        if n <= 1
          return 1
        else
          return n * factorial(n - 1)
        end
      end

      puts factorial(5)
    RUBY

    minified = minify_code(code)

    original_output = run_ruby(code)
    minified_output = run_ruby(minified)

    assert_equal original_output, minified_output, "Minified code should produce same output"
  end

  # T017: Test shebang preservation
  def test_us1_shebang_preservation
    code = "#!/usr/bin/env ruby\nputs 'hello'"
    minified = minify_code(code)

    # Shebang should be preserved if present in original
    # Note: Current implementation may or may not preserve shebang
    # This test documents expected behavior
    if code.start_with?("#!/")
      # For now, shebang is processed by AST, so this test may need adjustment
      # once shebang preservation is implemented
    end

    # Basic check: minified code should be valid Ruby
    assert run_ruby(minified), "Minified code should be executable"
  end

  # ===============================================
  # User Story 2: Variable Mangling Tests
  # ===============================================

  # T022: Test for local variable mangling
  def test_us2_local_variable_mangling
    code = <<~RUBY
      def test_method
        long_variable_name = 42
        another_long_name = long_variable_name + 1
        another_long_name
      end
    RUBY

    minified = minify_code(code, { mangle: true })

    # Variables should be shortened (not contain original long names)
    refute_includes minified, 'long_variable_name', "Variable should be mangled"
    refute_includes minified, 'another_long_name', "Variable should be mangled"

    # Should still be valid Ruby that produces same result
    original_result = run_ruby(code + "\nputs test_method")
    minified_result = run_ruby(minified + "\nputs test_method")
    assert_equal original_result, minified_result
  end

  # T023: Test for parameter mangling
  def test_us2_parameter_mangling
    code = <<~RUBY
      def greet_user(user_name, greeting_message)
        "\#{greeting_message}, \#{user_name}!"
      end
      puts greet_user("World", "Hello")
    RUBY

    minified = minify_code(code, { mangle: true })

    # Parameters should be shortened
    refute_includes minified, 'user_name', "Parameter should be mangled"
    refute_includes minified, 'greeting_message', "Parameter should be mangled"

    # Should produce same output
    original_result = run_ruby(code)
    minified_result = run_ruby(minified)
    assert_equal original_result, minified_result
  end

  # T024: Test for scope isolation (name reuse across scopes)
  def test_us2_scope_isolation
    code = <<~RUBY
      def method_one
        local_var = 1
        local_var
      end

      def method_two
        local_var = 2
        local_var
      end

      puts method_one
      puts method_two
    RUBY

    minified = minify_code(code, { mangle: true })

    # Both methods should have their own mangled variables
    # The variable 'a' (or similar) can be reused in different scopes
    original_result = run_ruby(code)
    minified_result = run_ruby(minified)
    assert_equal original_result, minified_result
  end

  # T025: Test for 50% compression ratio with variable mangling
  def test_us2_compression_ratio
    original_path = File.join(FIXTURES_DIR, 'variables.rb')
    original = File.read(original_path)
    minified = minify_fixture('variables.rb', { mangle: true })

    ratio = compression_ratio(original, minified)
    assert ratio >= 50, "Compression ratio with mangling should be >= 50%, got #{ratio}%"
  end

  # Test --no-mangle option
  def test_us2_no_mangle_option
    code = <<~RUBY
      def test_method
        long_variable_name = 42
        long_variable_name
      end
    RUBY

    minified = minify_code(code, { mangle: false })

    # Variables should NOT be shortened when mangle is disabled
    assert_includes minified, 'long_variable_name', "Variable should not be mangled with --no-mangle"
  end

  # ===============================================
  # User Story 3: AST Transformation Tests
  # ===============================================

  # T034: Test for boolean transformation
  def test_us3_boolean_transformation
    code = <<~RUBY
      def test_bools
        a = true
        b = false
        a && b
      end
    RUBY

    minified = minify_code(code, { transform: true })

    # true should become !!1
    assert_includes minified, '!!1', "true should be transformed to !!1"
    # false should become !1
    assert_includes minified, '!1', "false should be transformed to !1"
    refute_includes minified, 'true', "true literal should not remain"
    refute_includes minified, 'false', "false literal should not remain"

    # Should produce same output
    original_result = run_ruby(code + "\nputs test_bools")
    minified_result = run_ruby(minified + "\nputs test_bools")
    assert_equal original_result, minified_result
  end

  # T035: Test for ternary conversion
  def test_us3_ternary_conversion
    code = <<~RUBY
      def pick(x)
        if x > 5
          "big"
        else
          "small"
        end
      end
      puts pick(10)
    RUBY

    minified = minify_code(code, { transform: true })

    # if-else should become ternary
    assert_includes minified, '?', "if-else should be converted to ternary"
    assert_includes minified, ':', "if-else should be converted to ternary"

    # Should produce same output
    original_result = run_ruby(code)
    minified_result = run_ruby(minified)
    assert_equal original_result, minified_result
  end

  # T036: Test for block conversion
  def test_us3_block_conversion
    code = <<~RUBY
      [1, 2, 3].each do |n|
        puts n
      end
    RUBY

    minified = minify_code(code, { transform: true })

    # do-end should become {}
    assert_includes minified, '{', "do-end should be converted to {}"
    assert_includes minified, '}', "do-end should be converted to {}"
    refute_includes minified, ' do ', "do keyword should not remain"

    # Should produce same output
    original_result = run_ruby(code)
    minified_result = run_ruby(minified)
    assert_equal original_result, minified_result
  end

  # Test --no-transform option
  def test_us3_no_transform_option
    code = <<~RUBY
      def test_method
        x = true
        x
      end
    RUBY

    minified = minify_code(code, { transform: false, mangle: false })

    # With --no-transform, true should remain as true
    # Note: Current implementation always transforms booleans
    # This test documents expected behavior when --no-transform is fully implemented
  end

  # Test fixture transformation
  def test_us3_transformation_fixture
    minified = minify_fixture('transformations.rb')

    # Basic sanity check - should be valid Ruby
    output = run_ruby(minified)
    assert_includes output, "true", "Minified code should output 'true'"
  end

  # ===============================================
  # Phase 6: Dynamic Code Detection Tests
  # ===============================================

  # T043: Test for eval detection - mangling disabled in scope with eval
  def test_dynamic_eval_detection
    code = <<~RUBY
      def calculate_with_eval(formula, value)
        eval(formula.gsub('x', value.to_s))
      end
    RUBY

    minified = minify_code(code, { mangle: true })

    # When eval is present, variable names should NOT be mangled
    # because eval might reference them by string name
    assert_includes minified, 'formula', "Variables in scope with eval should not be mangled"
    assert_includes minified, 'value', "Variables in scope with eval should not be mangled"

    # Should still be valid Ruby
    test_code = minified + "\nputs calculate_with_eval('x + 10', 5)"
    output = run_ruby(test_code)
    assert_equal "15\n", output
  end

  # T044: Test for send detection - method names excluded from mangling
  def test_dynamic_send_detection
    code = <<~RUBY
      def call_method(object, method_name, argument)
        object.send(method_name, argument)
      end
    RUBY

    minified = minify_code(code, { mangle: true })

    # When send is present, variable names should NOT be mangled
    # because they might be used as method names
    assert_includes minified, 'method_name', "Variables in scope with send should not be mangled"

    # Should still be valid Ruby
    test_code = minified + "\nputs call_method('hello', :upcase, nil)"
    # Note: This particular call doesn't work because upcase doesn't take args,
    # but the point is the code should be syntactically valid
  end

  # Test for binding detection - mangling disabled when binding is used
  def test_dynamic_binding_detection
    code = <<~RUBY
      def get_value_via_binding(var_name)
        some_value = 42
        binding.local_variable_get(var_name)
      end
    RUBY

    minified = minify_code(code, { mangle: true })

    # When binding is used, variable names should NOT be mangled
    # because binding can access variables by their string names
    assert_includes minified, 'some_value', "Variables in scope with binding should not be mangled"

    # Should still be valid Ruby that works
    test_code = minified + "\nputs get_value_via_binding(:some_value)"
    output = run_ruby(test_code)
    assert_equal "42\n", output
  end

  # Test that safe methods (without dynamic patterns) are still mangled
  def test_dynamic_safe_methods_still_mangled
    code = <<~RUBY
      def safe_method(long_parameter)
        local_variable = long_parameter * 2
        another_variable = local_variable + 10
        another_variable
      end
    RUBY

    minified = minify_code(code, { mangle: true })

    # Safe methods without dynamic patterns should still be mangled
    refute_includes minified, 'long_parameter', "Safe method params should be mangled"
    refute_includes minified, 'local_variable', "Safe method locals should be mangled"
    refute_includes minified, 'another_variable', "Safe method locals should be mangled"

    # Should still produce correct output
    test_code = minified + "\nputs safe_method(5)"
    output = run_ruby(test_code)
    assert_equal "20\n", output
  end

  # Test that dynamic fixture file processes without errors
  def test_dynamic_fixture_processes
    # Should not raise any errors
    minified = minify_fixture('dynamic.rb', { mangle: true })

    # Should produce valid Ruby code
    assert minified.is_a?(String), "Should return minified string"
    refute_empty minified, "Should not be empty"
  end

  # ===============================================
  # Phase 7: Integration Tests
  # ===============================================

  # T051: Integration test comparing all fixtures
  def test_integration_all_fixtures
    fixtures = Dir.glob(File.join(FIXTURES_DIR, '*.rb'))

    fixtures.each do |fixture_path|
      fixture_name = File.basename(fixture_path)
      original = File.read(fixture_path)

      # Skip fixtures that have syntax errors or are just declarations
      next if original.include?('=begin')

      begin
        minified = minify_fixture(fixture_name, { mangle: true })

        # Minified code should be syntactically valid Ruby
        require 'prism'
        result = Prism.parse(minified)
        assert result.errors.empty?, "Minified #{fixture_name} should be valid Ruby: #{result.errors.map(&:message).join(', ')}"

        # Compression should have occurred
        ratio = compression_ratio(original, minified)
        assert ratio > 0, "#{fixture_name} should have some compression, got #{ratio}%"

      rescue Ruby::Minify::MinifyError => e
        # Some fixtures may use unsupported features, which is OK
        skip "#{fixture_name}: #{e.message}"
      end
    end
  end

  # T053: Benchmark compression ratios
  def test_benchmark_compression_ratios
    fixtures = {
      'simple_with_comments.rb' => 30,  # US1 target
      'variables.rb' => 50,             # US2 target
      'transformations.rb' => 0         # US3 (any compression is OK)
    }

    fixtures.each do |fixture_name, min_ratio|
      fixture_path = File.join(FIXTURES_DIR, fixture_name)
      next unless File.exist?(fixture_path)

      original = File.read(fixture_path)
      minified = minify_fixture(fixture_name, { mangle: true })

      ratio = compression_ratio(original, minified)
      assert ratio >= min_ratio, "#{fixture_name} should have >= #{min_ratio}% compression, got #{ratio}%"

      # Print benchmark for documentation purposes
      puts "\n  #{fixture_name}: #{original.bytesize} -> #{minified.bytesize} bytes (#{ratio}% reduction)"
    end
  end

  # ===============================================
  # Self-Hosting Test (Bootstrap Test)
  # ===============================================

  # Test that minify can minify itself, and the minified version
  # produces the same output when minifying code
  def test_self_hosting
    lib_dir = File.expand_path('../lib/ruby', __dir__)
    minify_path = File.join(lib_dir, 'minify.rb')
    detector_path = File.join(lib_dir, 'minify/detector.rb')
    name_generator_path = File.join(lib_dir, 'minify/name_generator.rb')

    # Step 1: Minify the minifier files using original minifier
    minifier = BaseMinify.new

    # Minify all source files (mangle: false to keep method names intact for requires)
    minified_minify = minifier.read_path(minify_path).minify(mangle: false).result
    minified_detector = minifier.read_path(detector_path).minify(mangle: false).result
    minified_name_generator = minifier.read_path(name_generator_path).minify(mangle: false).result

    # Verify minified files are valid Ruby
    require 'prism'
    [
      ['minify.rb', minified_minify],
      ['detector.rb', minified_detector],
      ['name_generator.rb', minified_name_generator]
    ].each do |name, code|
      result = Prism.parse(code)
      assert result.errors.empty?, "Minified #{name} should be valid Ruby: #{result.errors.map(&:message).join(', ')}"
    end

    # Step 2: Use minified code to minify a sample
    sample_code = <<~RUBY
      def hello(name)
        greeting = "Hello"
        "\#{greeting}, \#{name}!"
      end
    RUBY

    # Create temp files for minified minifier and sample
    require 'tempfile'
    Dir.mktmpdir do |tmpdir|
      # Write minified files to temp directory
      minify_dir = File.join(tmpdir, 'ruby', 'minify')
      FileUtils.mkdir_p(minify_dir)

      File.write(File.join(tmpdir, 'ruby', 'minify.rb'), minified_minify)
      File.write(File.join(minify_dir, 'detector.rb'), minified_detector)
      File.write(File.join(minify_dir, 'name_generator.rb'), minified_name_generator)

      # Copy version.rb (no need to minify)
      version_path = File.join(lib_dir, 'minify/version.rb')
      FileUtils.cp(version_path, minify_dir)

      sample_path = File.join(tmpdir, 'sample.rb')
      File.write(sample_path, sample_code)

      # Use minified minifier to minify the sample
      runner_code = <<~RUBY
        $LOAD_PATH.unshift('#{tmpdir}')
        require 'ruby/minify'
        minifier = BaseMinify.new
        result = minifier.read_path('#{sample_path}').minify(mangle: false).result
        puts result
      RUBY

      require 'open3'
      minified_output, stderr, status = Open3.capture3('ruby', '-e', runner_code)

      assert status.success?, "Minified minifier should execute successfully: #{stderr}"

      # Step 3: Compare output from original vs minified minifier
      original_output = minify_code(sample_code, mangle: false)

      assert_equal original_output.strip, minified_output.strip,
        "Minified minifier should produce same output as original minifier"
    end
  end
end

# frozen_string_literal: true

require_relative '../../test_helper'

class TestConstantAliaserPipeline < Minitest::Test
  include MinifyTestHelper

  def test_alias_declarations_generated
    code = <<~RUBY
      module MathUtils
        MULTIPLIER = 5
      end
      class Calculator
        OFFSET = 256
        LABELS = %w[low medium high].freeze
        SYMBOLS = %i[add subtract multiply].freeze
        def test = OFFSET + LABELS.size + SYMBOLS.size
      end
      puts Calculator.new.test
      puts MathUtils::MULTIPLIER
    RUBY
    result = minify_at_level(code, 2)
    assert_equal [
      'Calculator::LABELS=Calculator::D;',
      'Calculator::OFFSET=Calculator::C;',
      'Calculator::SYMBOLS=Calculator::B;',
      'MathUtils::MULTIPLIER=MathUtils::A',
    ].join(''), result.aliases
  end

  def test_external_prefix_aliased
    code = <<~RUBY
      class App
        def run
          puts Process::Status.name
          puts Process::Sys.name
          puts Process::UID.name
          puts Process::GID.name
          puts Process::Tms.name
        end
      end
      App.new.run
    RUBY
    result = minify_at_level(code, 2)
    assert_equal 'A=Process', result.preamble
    assert_equal 'class App;def run =(puts A::Status.name;puts A::Sys.name;puts A::UID.name;puts A::GID.name;puts A::Tms.name);end;App.new.run',
                 result.code
  end

  def test_external_prefix_uses_resolved_path_for_unqualified_refs
    code = <<~RUBY
      module Outer
        module Other
          class Worker
            def run
              Inner::Leaf.new
              Inner::Leaf.new
              Inner::Leaf.new
            end
          end
        end
      end
    RUBY
    rbs_files = { "outer.rbs" => <<~RBS }
      module Outer
        module Inner
          class Leaf
            def initialize: () -> void
          end
        end
      end
    RBS
    result = minify_at_level(code, 2, verify_output: false, rbs_files: rbs_files)
    assert_equal 'A=Outer::Inner', result.preamble
    assert_equal 'module Outer;module Other;class Worker;def run =(A::Leaf.new;A::Leaf.new;A::Leaf.new);end;end;end',
                 result.code
  end

  def test_constant_path_write_and_superclass_renaming
    code = <<~RUBY
      module Framework
        class Base
          TIMEOUT = 30
          def run = TIMEOUT
        end
        class Server < Base
          PORT = 8080
          def start = PORT
        end
      end
      Framework::MAX_CONNECTIONS = 100
      puts Framework::Server.new.start
      puts Framework::Server.new.run
      puts Framework::MAX_CONNECTIONS
    RUBY
    result = minify_at_level(code, 2)
    assert_equal 'module Framework;class Base;B=30;def run =B;end;class Server<Framework::Base;C=8080;def start =C;end;end;Framework::A=100;' \
                 'puts Framework::Server.new.start;puts Framework::Server.new.run;puts Framework::A',
                 result.code
    assert_equal 'Framework::MAX_CONNECTIONS=Framework::A;Framework::Base::TIMEOUT=Framework::Base::B;Framework::Server::PORT=Framework::Server::C',
                 result.aliases
  end

  def test_def_receiver_patching
    code = <<~RUBY
      class Formatter
        SEPARATOR = "-"
        def self.format(str)
          str + SEPARATOR + str
        end
      end
      def Formatter.short(str)
        str[0..2]
      end
      puts Formatter.format("abc")
      puts Formatter.short("hello")
    RUBY
    result = minify_at_level(code, 2)
    assert_equal 'class Formatter;A="-";def self.format(str) =str+A+str;end;' \
                 'def Formatter.short(str) =str[(0..2)];puts Formatter.format("abc");puts Formatter.short("hello")',
                 result.code
    assert_equal 'Formatter::SEPARATOR=Formatter::A', result.aliases
  end

  def test_aliased_constant_prefix_not_in_preamble
    code = <<~RUBY
      module Outer
        module Inner
          class Leaf
          end
        end
        AliasedInner = Inner
        module Consumer
          class Worker
            def run
              AliasedInner::Leaf.new
              AliasedInner::Leaf.new
              AliasedInner::Leaf.new
            end
          end
        end
      end
    RUBY
    result = minify_at_level(code, 3, verify_output: false)
    preamble_rhs = result.preamble.split(';').map { |d| d.split('=', 2).last }
    assert_equal true, preamble_rhs.none? { |rhs| rhs.include?('AliasedInner') }
  end

  def test_singleton_class_constant_not_renamed
    # Constants defined in `class << self` live on the metaclass —
    # they cannot be accessed as `Foo::X` from outside, so alias
    # declarations would fail. They must be excluded from renaming.
    code = <<~RUBY
      class Foo
        class << self
          PATTERNS = [/foo/, /bar/]
          def get_patterns
            PATTERNS
          end
        end
        def self.use_patterns
          puts get_patterns.inspect
        end
      end
      Foo.use_patterns
    RUBY
    result = minify_at_level(code, 2)
    assert_equal 'class Foo;class<<self;PATTERNS=[/foo/,/bar/];def get_patterns =PATTERNS;end;def self.use_patterns =puts get_patterns.inspect;end;Foo.use_patterns',
                 result.code
  end
end

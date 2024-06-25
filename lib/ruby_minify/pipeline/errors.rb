# frozen_string_literal: true

module RubyMinify
  module Pipeline
    # Base error class for all pipeline stage errors
    class StageError < StandardError; end

    # Raised when a required file cannot be found
    class FileNotFoundError < StageError
      attr_reader :path, :required_from, :line

      def initialize(path, required_from: nil, line: nil)
        @path = path
        @required_from = required_from
        @line = line

        message = "File not found: #{path}"
        message += " (required from #{required_from}:#{line})" if required_from && line
        super(message)
      end
    end

    # Raised when a dynamic require or autoload is detected
    class DynamicRequireError < StageError
      attr_reader :path, :line, :expression

      def initialize(path, line:, expression:)
        @path = path
        @line = line
        @expression = expression

        super("Dynamic require at #{path}:#{line}: #{expression}")
      end
    end

    # Raised when a circular dependency is detected in the graph
    class CircularDependencyError < StageError
      attr_reader :cycle

      def initialize(cycle)
        @cycle = cycle

        cycle_str = cycle.map { |p| File.basename(p) }.join(' → ')
        super("Circular dependency: #{cycle_str}")
      end
    end

    # Raised when no files are provided to the minifier
    class NoFilesError < StageError
      def initialize
        super("No files provided. Please provide an entry point file.")
      end
    end
  end
end

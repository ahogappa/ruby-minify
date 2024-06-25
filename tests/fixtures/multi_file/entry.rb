# Entry point file for multi-file minification tests
require_relative 'lib/dependency_a'
require_relative 'lib/dependency_b'

module MyApplication
  class Main
    def initialize
      @processor = DependencyA::Processor.new
      @formatter = DependencyB::Formatter.new
    end

    def run(input_data)
      processed = @processor.process(input_data)
      @formatter.format(processed)
    end

    def version
      "#{DependencyA::VERSION}.#{DependencyB::VERSION}"
    end
  end
end


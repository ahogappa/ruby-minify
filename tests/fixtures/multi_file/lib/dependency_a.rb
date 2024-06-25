# Dependency A - Processor module
require_relative 'nested/dependency_c'

module DependencyA
  VERSION = "1.0"

  class Processor
    def initialize
      @helper = DependencyC::Helper.new
    end

    def process(input_data)
      cleaned = @helper.clean(input_data)
      transform(cleaned)
    end

    private

    def transform(data)
      data.to_s.upcase
    end
  end
end

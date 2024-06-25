# Entry file that shares dependency_b with entry.rb
require_relative 'lib/dependency_b'

module SharingApp
  class Runner
    def run
      formatter = DependencyB::Formatter.new
      formatter.format("hello")
    end
  end
end

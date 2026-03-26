# frozen_string_literal: true

module MyLib
  autoload :Formatter, "my_lib/formatter"

  class Runner
    def run
      Formatter.new.format("hello")
    end
  end
end

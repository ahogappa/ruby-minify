# Dependency B - Formatter module
module DependencyB
  VERSION = "2.0"

  class Formatter
    def format(data)
      "[FORMATTED] #{data}"
    end

    def wrap(data, prefix, suffix)
      "#{prefix}#{data}#{suffix}"
    end
  end
end

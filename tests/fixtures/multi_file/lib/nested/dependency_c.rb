# Dependency C - Helper module (nested dependency)
module DependencyC
  VERSION = "0.1"

  class Helper
    def clean(input_data)
      input_data.to_s.strip
    end

    def sanitize(input_data)
      input_data.to_s.gsub(/[^a-zA-Z0-9\s]/, '')
    end
  end
end

# Independent file B - no require_relative to other independent files
module IndependentB
  VERSION = "2.0"

  class Logger
    def log(message)
      "[LOG] #{message}"
    end

    def warn(message)
      "[WARN] #{message}"
    end
  end
end

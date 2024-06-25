# Independent file A - no require_relative to other independent files
module IndependentA
  VERSION = "1.0"

  class Calculator
    def add(x, y)
      x + y
    end

    def multiply(x, y)
      x * y
    end
  end
end

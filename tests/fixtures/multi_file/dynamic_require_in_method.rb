# frozen_string_literal: true

require_relative 'lib/dependency_a'

class DynamicLoader
  def load_feature(name)
    require(name)
  end

  def load_relative(path)
    require_relative(path)
  end
end

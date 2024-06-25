# frozen_string_literal: true

class Base
  def name
    self.class.name
  end
end

class Widget < Base
  require_relative 'widget/helper'

  def display
    Helper.format(name)
  end
end

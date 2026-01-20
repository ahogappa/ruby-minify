# frozen_string_literal: true

module Ruby
  module Minify
    # Constants for detecting dynamic code patterns
    module Detector
      # Methods that can access variables by string/symbol name
      # Used to disable variable mangling in scopes containing these calls
      DYNAMIC_METHODS = %i[
        eval
        instance_eval
        class_eval
        module_eval
        binding
        local_variable_get
        local_variable_set
        send
        __send__
        public_send
        method
        define_method
        respond_to?
      ].freeze
    end
  end
end

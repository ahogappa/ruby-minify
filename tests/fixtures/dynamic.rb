# Test fixture for dynamic code patterns
# These patterns should disable variable mangling to prevent breakage

# Pattern 1: eval with variable interpolation
def calculate_with_eval(formula, value)
  eval(formula.gsub('x', value.to_s))
end

# Pattern 2: binding usage
def get_value_via_binding(var_name)
  some_value = 42
  another_value = 100
  binding.local_variable_get(var_name)
end

# Pattern 3: send with dynamic method
def call_method(object, method_name, argument)
  object.send(method_name, argument)
end

# Pattern 4: method reference
def get_method_reference(object, name)
  object.method(name)
end

# Pattern 5: respond_to? check
def safe_call(object, method_name)
  if object.respond_to?(method_name)
    object.send(method_name)
  end
end

# Pattern 6: define_method (dynamic method definition)
class DynamicClass
  %w[foo bar baz].each do |name|
    define_method(name) do |arg|
      "#{name}: #{arg}"
    end
  end
end

# Safe code that CAN be mangled (no dynamic patterns)
def safe_method(long_parameter)
  local_variable = long_parameter * 2
  another_variable = local_variable + 10
  another_variable
end

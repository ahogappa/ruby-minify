# Test file for variable mangling
# Contains long variable names and nested scopes

def calculate_total(item_price, quantity, tax_rate)
  subtotal = item_price * quantity
  tax_amount = subtotal * tax_rate
  total_amount = subtotal + tax_amount
  total_amount
end

def process_data(input_data)
  processed_result = input_data.map { |element| element * 2 }
  processed_result
end

result = calculate_total(100, 5, 0.1)
puts result

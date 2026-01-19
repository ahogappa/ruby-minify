# Test file for AST transformations
# Contains booleans, if-else, and do-end blocks

def check_value(value)
  if value > 10
    return true
  else
    return false
  end
end

def process_items(items)
  items.each do |item|
    puts item
  end
end

result = check_value(15)
puts result

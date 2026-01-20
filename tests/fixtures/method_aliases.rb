# Test fixture for method alias shortening
# This file tests all 14 method alias replacements
# Uses long method names that should be replaced with shorter aliases

# Array methods (Enumerable)
result1 = [1, 2, 3].collect { |x| x * 2 }
result2 = [1, 2, 3].detect { |x| x > 1 }
result3 = [1, 2, 3].find_all { |x| x > 1 }
result4 = [[1], [2]].collect_concat { |x| x }
result5 = [1, 2, 3].find_index(2)
arr = [1, 2, 3].collect! { |x| x * 2 }

# Hash methods (using literals for type detection)
result6 = { a: 1, b: 2 }.has_key?(:a)
result7 = { a: 1, b: 2 }.has_value?(1)
{ a: 1, b: 2 }.each_pair { |k, v| puts "#{k}: #{v}" }

# Numeric methods
result8 = (-5).magnitude
result9 = (-3.5).magnitude

# String methods
result10 = "hello".length

# Symbol methods
result11 = :symbol.id2name

# Object methods (universal)
result12 = [1, 2, 3].kind_of?(Array)
result13 = "test".yield_self { |s| s.upcase }

# Chained methods (for US2 testing)
chained = [1, 2, 3, 4, 5].find_all { |x| x > 2 }.collect { |x| x * 10 }

puts result1.inspect
puts result2.inspect
puts result3.inspect
puts result4.inspect
puts result5.inspect
puts arr.inspect
puts result6.inspect
puts result7.inspect
puts result8.inspect
puts result9.inspect
puts result10.inspect
puts result11.inspect
puts result12.inspect
puts result13.inspect
puts chained.inspect

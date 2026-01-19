# Ruby::Minify

A Ruby code minifier that uses TypeProf for intelligent variable name mangling and AST-based transformations to achieve high compression rates while preserving functional equivalence.

## Features

- **Whitespace & Comment Removal**: Strips all unnecessary whitespace and comments
- **Variable Mangling**: Shortens local variable and parameter names (a, b, c, ..., aa, ab, ...)
- **AST Transformations**: Converts `true` to `!!1`, `false` to `!1`, `if-else` to ternary operators, and `do-end` blocks to `{}`
- **Dynamic Code Detection**: Automatically disables mangling in scopes containing `eval`, `binding`, `send`, etc. to prevent runtime breakage
- **Scope-Aware**: Uses TypeProf's variable tracking to ensure correct mangling across nested scopes

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby-minify'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install ruby-minify

## Usage

### Command Line

```bash
# Basic minification (output to stdout)
bin/minify path/to/file.rb

# Write to output file
bin/minify path/to/file.rb --output minified.rb
bin/minify path/to/file.rb -o minified.rb

# Disable variable mangling
bin/minify path/to/file.rb --no-mangle

# Disable AST transformations
bin/minify path/to/file.rb --no-transform

# Show help
bin/minify --help

# Show version
bin/minify --version
```

### Ruby API

```ruby
require 'ruby/minify'

minifier = BaseMinify.new

# Minify a file
minifier.read_path('path/to/file.rb').minify
puts minifier.result

# With options
minifier.read_path('path/to/file.rb').minify(mangle: true, transform: true)

# Output to file
minifier.output('output.rb')
```

## Compression Benchmarks

| File Type | Original | Minified | Compression |
|-----------|----------|----------|-------------|
| Comments & whitespace | 245 bytes | 56 bytes | **77%** |
| Long variable names | 430 bytes | 139 bytes | **68%** |
| Boolean/control flow | 285 bytes | 116 bytes | **59%** |

Target compression rates:
- Basic minification (US1): 30%+
- With variable mangling (US2): 50%+
- With all transformations (US3): 55%+

## Dynamic Code Safety

The minifier automatically detects dynamic code patterns and disables variable mangling in affected scopes to prevent runtime breakage:

- `eval`, `instance_eval`, `class_eval`, `module_eval`
- `binding`, `local_variable_get`, `local_variable_set`
- `send`, `__send__`, `public_send`
- `method`, `define_method`, `respond_to?`

Example:
```ruby
# Input
def calculate(formula, value)
  eval(formula.gsub('x', value.to_s))
end

# Output (variables NOT mangled due to eval)
def calculate(formula,value);eval(formula.gsub("x",value.to_s));end
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | File not found |
| 2 | Syntax error in source |
| 3 | Internal minification error |

## Dependencies

- [TypeProf](https://github.com/ruby/typeprof) - For AST parsing and variable tracking
- [Prism](https://github.com/ruby/prism) - For syntax validation

## Development

After checking out the repo, run `bin/setup` to install dependencies. Run tests with:

```bash
bundle exec ruby tests/test_minify.rb
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ahogappa/ruby-minify.

## License

The gem is available as open source under the terms of the MIT License.

# RubyMinify

A Ruby code minifier that uses [TypeProf](https://github.com/ruby/typeprof) for type-aware analysis and AST-based transformations to achieve high compression rates while preserving functional equivalence.

## Philosophy

This project takes an **aggressive optimization** approach. In Ruby, even comment removal requires context awareness — for example, `foo\n# comment\n.to_s` works because the comment connects the method chain, but removing it causes a syntax error. Whether a given comment is safe to remove depends entirely on context, making the boundary between safe and unsafe transformations inherently blurry. Since conservative minification is already difficult in Ruby, we choose to optimize as aggressively as possible. TypeProf's type analysis helps make these transformations more informed, but the goal is always maximum compression.

## Features

- **Multi-file support**: Follows `require_relative` to collect and concatenate dependencies into a single output
- **Whitespace & comment removal**: Strips all unnecessary whitespace and comments
- **Variable mangling**: Shortens local variable and parameter names (a, b, ..., z, a0, a1, ..., z9, a0a, ...)
- **Constant shortening**: Renames user-defined classes/modules to shorter names (A, B, ..., Z, A0, A1, ..., Z9, A0A, ...)
- **Method renaming**: Shortens user-defined method names based on cost-benefit analysis
- **Instance variable renaming**: Shortens instance variables per class, coordinated with `attr_reader`/`attr_writer`/`attr_accessor`
- **Keyword argument renaming**: Shortens keyword parameter names with hash shorthand coordination
- **Method alias shortening**: Replaces long stdlib method names with shorter aliases (e.g., `collect` -> `map`, `detect` -> `find`)
- **External prefix aliasing**: Shortens repeated external constant paths (e.g., `TypeProf::Core::AST` -> `A`)
- **AST transformations**:
  - `true` -> `!!1`, `false` -> `!1`
  - `if-else` -> ternary, `do-end` -> `{}`
  - Postfix `while`/`until` for single-statement bodies
  - Endless method syntax for single-expression `def` bodies
  - `class << self` block for consecutive `def self.` methods
  - `%i[]` for symbol arrays with 3+ elements
- **Dead code elimination**: Removes unreachable code after `return`, `break`, `next`, `raise`
- **RuboCop preprocessing**: Applies safe autocorrections before minification
- **Dynamic code detection**: Disables mangling in scopes containing `eval`, `binding`, `send`, etc.

## Installation

```ruby
gem 'ruby-minify'
```

## Usage

### Command Line

```bash
# Minify a file (follows require_relative automatically)
bin/minify path/to/entry.rb

# Write to output file
bin/minify path/to/entry.rb -o minified.rb

# Write constant aliases to a separate file (only generated at L2+)
bin/minify path/to/entry.rb -o minified.rb -a aliases.rb

# Multiple entry points
bin/minify file1.rb file2.rb

# Show version
bin/minify -v
```

### Ruby API

```ruby
require 'ruby_minify'

minifier = RubyMinify::Minifier.new
result = minifier.call('path/to/entry.rb')

puts result.content           # minified code
puts result.aliases           # constant alias declarations (empty at L0-L1)
puts result.stats.file_count  # number of files processed
puts result.stats.compression_ratio  # e.g., 0.44 (56% reduction)

# Specify optimization level (0-5, default: 3)
result = minifier.call('path/to/entry.rb', level: 5)
```

## Optimization Levels

The default level is **3** (safe compression). Levels 0-3 are safe transformations that preserve all public interfaces. Levels 4-5 are aggressive and may break code that relies on reflection or variable/method name inspection.

| Level | Transformations | Safety |
|-------|----------------|--------|
| 0 | Whitespace/comment removal only (AST rebuild) | Safe |
| 1 | + Boolean/char/constant folding, control flow simplification, endless methods, paren removal | Safe |
| 2 | + Constant aliasing | Safe |
| 3 | + Keyword argument renaming | Safe |
| 4 | + Instance/class/global variable renaming | Aggressive |
| 5 | + Method renaming, attr-backed ivar coordination | Aggressive |

## Development

```bash
bundle install

# Run tests (fast, excludes self-hosting)
rake test

# Run all tests including self-hosting
rake test:all

# Run self-hosting test only
rake test:integration

# Run gem integration tests (minifies real gems and runs their test suites)
rake test:gems

# Show compression ratio on self-hosting
rake benchmark
```

## Architecture

The minification pipeline:

```
FileCollector → Concatenator → Preprocessor → Compactor → STAGES[level] → Output
```

1. **FileCollector** — Resolves `require_relative` / `autoload` and collects all source files into a dependency graph
2. **Concatenator** — Topologically sorts files and concatenates them into a single source
3. **Preprocessor** — Applies RuboCop safe autocorrections (redundant return/self, symbol proc, etc.)
4. **Compactor** — Rebuilds the AST into minimal whitespace form (L0 baseline)
5. **STAGES** — Table-driven stage pipeline, configured per level:
   - **Simple stages** (bare Class): `BooleanShorten`, `CharShorten`, `ConstantFold`, `ControlFlowSimplify`, `EndlessMethod`, `ParenOptimizer` — each transforms `String → String`
   - **Rename stages** (Array `[Class, kwargs]`): `ConstantAliaser`, `VariableRenamer`, `MethodRenamer` — run via `UnifiedRenamer` with a single TypeProf analysis pass

## Dependencies

- [TypeProf](https://github.com/ruby/typeprof) - Type-aware AST analysis
- [Prism](https://github.com/ruby/prism) - Syntax validation
- [RuboCop](https://github.com/rubocop/rubocop) - Preprocessing autocorrections

## License

The gem is available as open source under the terms of the MIT License.

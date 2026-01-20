# frozen_string_literal: true

module Ruby
  module Minify
    # Method alias mappings for shortening Ruby method calls
    # Structure: { original_method => { shorter: shorter_name, classes: [applicable_classes] } }
    # Note: Using :shorter instead of :alias as 'alias' is a Ruby reserved keyword
    METHOD_ALIASES = {
      collect:        { shorter: :map,       classes: [:Array, :Enumerable] },
      collect!:       { shorter: :map!,      classes: [:Array] },
      detect:         { shorter: :find,      classes: [:Enumerable] },
      find_all:       { shorter: :select,    classes: [:Enumerable] },
      collect_concat: { shorter: :flat_map,  classes: [:Enumerable] },
      each_pair:      { shorter: :each,      classes: [:Hash] },
      has_key?:       { shorter: :key?,      classes: [:Hash] },
      has_value?:     { shorter: :value?,    classes: [:Hash] },
      find_index:     { shorter: :index,     classes: [:Array, :Enumerable] },
      magnitude:      { shorter: :abs,       classes: [:Integer, :Float, :Numeric] },
      kind_of?:       { shorter: :is_a?,     classes: [:Object] },
      yield_self:     { shorter: :then,      classes: [:Object] },
      id2name:        { shorter: :to_s,      classes: [:Symbol] },
      length:         { shorter: :size,      classes: [:String, :Array, :Hash] }
    }.freeze

    # Maps TypeProf AST node types to Ruby class symbols for type detection
    AST_TO_CLASS = {
      TypeProf::Core::AST::ArrayNode                => :Array,
      TypeProf::Core::AST::HashNode                 => :Hash,
      TypeProf::Core::AST::StringNode               => :String,
      TypeProf::Core::AST::InterpolatedStringNode   => :String,
      TypeProf::Core::AST::SymbolNode               => :Symbol,
      TypeProf::Core::AST::InterpolatedSymbolNode   => :Symbol,
      TypeProf::Core::AST::IntegerNode              => :Integer,
      TypeProf::Core::AST::FloatNode                => :Float,
      TypeProf::Core::AST::RangeNode                => :Range
    }.freeze

    # Classes that include the Enumerable module and inherit its method aliases
    ENUMERABLE_CLASSES = [:Array, :Hash, :Range, :Set, :Enumerator].freeze
  end
end

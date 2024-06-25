# frozen_string_literal: true

module RubyMinify
  # Method alias mappings: longer method name => shorter equivalent
  # TypeProf verifies at analysis time that the shorter method
  # is available on the receiver type via inheritance chain.
  METHOD_ALIASES = {
    collect:        :map,
    collect!:       :map!,
    detect:         :find,
    find_all:       :select,
    collect_concat: :flat_map,
    each_pair:      :each,
    has_key?:       :key?,
    has_value?:     :value?,
    find_index:     :index,
    magnitude:      :abs,
    kind_of?:       :is_a?,
    yield_self:     :then,
    id2name:        :to_s,
    length:         :size,
    entries:        :to_a,
    append:         :push,
    include?:       :key?,
    member?:        :key?,
    object_id:      :__id__,
    raise:          :fail,
  }.freeze

  # Structural method transforms: method call → different syntax
  # Applied only when TypeProf verifies receiver type compatibility.
  # Key: [method_name, :ClassName], Value: replacement string
  METHOD_TRANSFORMS = {
    [:first, :Array] => '[0]',
    [:zero?, :Numeric] => '==0',
    [:empty?, :Array] => '==[]',
    [:empty?, :String] => '==""',
    [:empty?, :Hash] => '=={}',
  }.freeze
end

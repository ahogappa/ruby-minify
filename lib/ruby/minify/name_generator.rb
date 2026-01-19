# frozen_string_literal: true

module Ruby
  module Minify
    # Generates sequential short names for variable mangling
    # Sequence: a, b, c, ..., z, aa, ab, ..., az, ba, ..., zz, aaa, ...
    class NameGenerator
      RESERVED_WORDS = %w[
        __FILE__ __LINE__ __ENCODING__ BEGIN END alias and begin break case
        class def defined? do else elsif end ensure false for if in module
        next nil not or redo rescue retry return self super then true undef
        unless until when while yield
      ].freeze

      LETTERS = ('a'..'z').to_a.freeze

      def initialize
        @index = 0
        @excluded = Set.new(RESERVED_WORDS)
      end

      # Generate next available name, skipping reserved words
      def next_name
        loop do
          name = index_to_name(@index)
          @index += 1
          return name unless @excluded.include?(name)
        end
      end

      # Reset generator for a new scope
      def reset
        @index = 0
      end

      # Exclude a name from being generated
      def exclude(name)
        @excluded << name.to_s
      end

      private

      # Convert index to name: 0->a, 25->z, 26->aa, 27->ab, etc.
      def index_to_name(index)
        return LETTERS[index] if index < 26

        result = ""
        n = index
        while n >= 0
          result = LETTERS[n % 26] + result
          n = n / 26 - 1
        end
        result
      end
    end
  end
end

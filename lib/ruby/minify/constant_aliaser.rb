# frozen_string_literal: true

require 'set'

module Ruby
  module Minify
    # Generates sequential short names for constant aliasing
    # Sequence: A, B, C, ..., Z, AA, AB, ..., AZ, BA, ..., ZZ, AAA, ...
    class ConstantNameGenerator
      LETTERS = ('A'..'Z').to_a.freeze

      def initialize
        @index = 0
        @excluded = Set.new
      end

      # Generate next available name, skipping excluded names
      def next_name
        loop do
          name = index_to_name(@index)
          @index = @index + 1
          return name unless @excluded.include?(name)
        end
      end

      # Exclude a name from being generated (to avoid collisions)
      def exclude(name)
        @excluded << name.to_s
      end

      private

      # Convert index to name: 0->A, 25->Z, 26->AA, 27->AB, etc.
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

    # Represents a user-defined constant found in the source file
    ConstantInfo = Struct.new(
      :original_name,   # Symbol - Original constant name (e.g., :MyClass)
      :full_path,       # Array<Symbol> - Full namespace path (e.g., [:Foo, :Bar, :MyClass])
      :short_name,      # String - Assigned short name (e.g., "A")
      :usage_count,     # Integer - Number of references in the file
      :definition_type, # Symbol - :class, :module, or :value
      :scope_path,      # Array<Symbol> - Module/class scope where defined
      keyword_init: true
    ) do
      def initialize(original_name: nil, full_path: nil, short_name: nil,
                     usage_count: nil, definition_type: nil, scope_path: nil)
        self.original_name = original_name
        self.full_path = full_path || []
        self.short_name = short_name
        self.usage_count = usage_count || 0
        self.definition_type = definition_type
        self.scope_path = scope_path || []
      end
    end

    # Tracks the mapping between original and short constant names
    # Uses static_cpath (full qualified path) as key to distinguish
    # constants with same name in different modules
    class ConstantAliasMapping
      attr_reader :mappings, :used_short_names, :existing_names

      def initialize
        @mappings = {}           # Hash<Array<Symbol>, ConstantInfo> - key is static_cpath
        @by_name = {}            # Hash<Symbol, Array<ConstantInfo>> - lookup by simple name
        @used_short_names = Set.new
        @existing_names = Set.new
        @state = :empty
      end

      def empty?
        @state == :empty
      end

      def frozen?
        @state == :frozen
      end

      # Add a constant definition using TypeProf's static_cpath
      def add_definition_with_path(static_cpath, definition_type:)
        raise "Cannot add definitions when frozen" if frozen?
        @state = :collecting if empty?

        return if @mappings.key?(static_cpath)

        name = static_cpath.last
        scope_path = static_cpath[0...-1]

        info = ConstantInfo.new(
          original_name: name,
          full_path: static_cpath,
          definition_type: definition_type,
          scope_path: scope_path
        )
        @mappings[static_cpath] = info

        # Also index by simple name for backward compatibility
        @by_name[name] = [] unless @by_name.key?(name)
        @by_name[name] << info
      end

      # Legacy method - add definition by name (for backward compatibility)
      def add_definition(name, definition_type:, scope_path: [])
        static_cpath = scope_path + [name]
        add_definition_with_path(static_cpath, definition_type: definition_type)
      end

      # Increment usage count for a constant by static_cpath
      def increment_usage_by_path(static_cpath)
        raise "Cannot increment usage when frozen" if frozen?
        return unless @mappings.key?(static_cpath)

        info = @mappings[static_cpath]
        info.usage_count = info.usage_count + 1
      end

      # Increment usage count by simple name (finds first match)
      def increment_usage(name)
        raise "Cannot increment usage when frozen" if frozen?
        return unless @by_name.key?(name)

        # Increment all constants with this name
        @by_name[name].each do |info|
          info.usage_count = info.usage_count + 1
        end
      end

      # Register an existing short name that should be skipped
      def register_existing_name(name)
        @existing_names << name
      end

      # Freeze the mapping and assign short names
      def freeze_mapping(name_generator)
        raise "Already frozen" if frozen?

        @state = :frozen

        # Sort by usage count (descending) for optimal compression
        sorted_constants = @mappings.values
                                    .select { |info| should_rename?(info) }
                                    .sort_by { |info| -info.usage_count }

        # Exclude existing short names
        @existing_names.each { |name| name_generator.exclude(name) }

        # Assign short names
        sorted_constants.each do |info|
          info.short_name = name_generator.next_name
          @used_short_names << info.short_name
        end
      end

      # Get short name for a constant by static_cpath
      def short_name_for_path(static_cpath)
        info = @mappings[static_cpath]
        info&.short_name
      end

      # Get short name for a constant by simple name (finds first match)
      # Used when static_cpath is not available
      def short_name_for(name)
        return nil unless @by_name.key?(name)
        infos = @by_name[name]
        return nil if infos.empty?
        # Return first match (for backward compatibility)
        infos.first&.short_name
      end

      # Check if a constant is user-defined by static_cpath
      def user_defined_path?(static_cpath)
        @mappings.key?(static_cpath)
      end

      # Generate alias statements grouped by scope
      # Top-level constants: "MyClass=A"
      # Scoped constants: "module Foo;Bar=B;end"
      def generate_aliases
        renamed = @mappings.values.select { |info| info.short_name }
        return [] if renamed.empty?

        # Group by scope_path
        by_scope = {}
        renamed.each do |info|
          scope_key = info.scope_path.empty? ? [] : info.scope_path
          by_scope[scope_key] = [] unless by_scope.key?(scope_key)
          by_scope[scope_key] << info
        end

        result = []

        # Generate aliases for each scope
        by_scope.each do |scope_path, infos|
          if scope_path.empty?
            # Top-level constants
            infos.each do |info|
              result << "#{info.original_name}=#{info.short_name}"
            end
          else
            # Scoped constants - wrap in module/class reopening
            scope_aliases = infos.map { |info| "#{info.original_name}=#{info.short_name}" }.join(";")
            # Build scope opening with correct class/module keyword and unambiguous short names
            current_path = []
            scope_opener = scope_path.map do |scope_name|
              current_path = current_path + [scope_name]
              # Lookup mapping to determine if class or module
              info = @mappings[current_path]
              keyword = (info&.definition_type == :class) ? "class" : "module"
              # Get unambiguous short name using full path
              short_scope = short_name_for_path(current_path) || scope_name.to_s
              "#{keyword} #{short_scope}"
            end.join(";")
            scope_closer = (["end"] * scope_path.size).join(";")
            result << "#{scope_opener};#{scope_aliases};#{scope_closer}"
          end
        end

        result
      end

      private

      # Determine if a constant should be renamed
      # Skip names that are 3 characters or less (no benefit)
      def should_rename?(info)
        info.original_name.to_s.length > 3
      end
    end

  end
end

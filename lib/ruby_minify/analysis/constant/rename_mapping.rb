# frozen_string_literal: true

require 'set'

module RubyMinify
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
  class ConstantRenameMapping
    attr_reader :mappings, :used_short_names

    def initialize
      @mappings = {}           # Hash<Array<Symbol>, ConstantInfo> - key is static_cpath
      @by_name = {}            # Hash<Symbol, Array<ConstantInfo>> - lookup by simple name
      @used_short_names = Set.new
      @state = :empty
    end

    def empty?
      @state == :empty
    end

    def finalized?
      @state == :frozen
    end

    # Add a constant definition using TypeProf's static_cpath
    def add_definition_with_path(static_cpath, definition_type:)
      raise "Cannot add definitions when finalized" if finalized?
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
      (@by_name[name] ||= []) << info
    end

    # Increment usage count for a constant by static_cpath
    def increment_usage_by_path(static_cpath)
      raise "Cannot increment usage when finalized" if finalized?
      return unless @mappings.key?(static_cpath)

      info = @mappings[static_cpath]
      info.usage_count += 1
    end

    # Increment usage count by simple name (finds first match)
    def increment_usage(name)
      raise "Cannot increment usage when finalized" if finalized?
      return unless @by_name.key?(name)

      # Increment all constants with this name
      @by_name[name].each do |info|
        info.usage_count += 1
      end
    end

    def exclude_path(static_cpath)
      raise "Cannot exclude when finalized" if finalized?
      info = @mappings.delete(static_cpath)
      return unless info
      name = static_cpath.last
      @by_name[name]&.reject! { |i| i.full_path == static_cpath }
    end

    # Freeze the mapping and assign short names
    def assign_short_names(name_generator, skip_class_modules: false)
      raise "Already finalized" if finalized?

      @state = :frozen

      # Collect all existing constant names for collision checking
      existing_names = Set.new(@mappings.values.map { |info| info.original_name.to_s })

      # Sort by estimated savings (original_length * occurrences) descending
      sorted_constants = @mappings.values
                                  .sort_by { |info| -(info.original_name.to_s.length * (info.usage_count + 1)) }

      # Pass 1: Tentatively assign short names
      candidate = nil
      sorted_constants.each do |info|
        # Skip class/module constants when not renaming them (L2-L4 safety)
        next if skip_class_modules && info.definition_type != :value
        # Skip class/module constants that already exist in the runtime
        # (reopened built-in classes like Array, String, etc.)
        next if info.definition_type != :value && runtime_constant?(info.full_path)

        if candidate.nil?
          candidate = name_generator.next_name
          candidate = name_generator.next_name while existing_names.include?(candidate)
        end

        original_len = info.original_name.to_s.length
        candidate_len = candidate.length
        saved_per_use = original_len - candidate_len
        next unless saved_per_use > 0

        # Count definition site + all reference sites
        total_occurrences = info.usage_count + 1
        total_savings = saved_per_use * total_occurrences
        next unless total_savings > 0

        info.short_name = candidate
        @used_short_names << candidate
        candidate = nil
      end

      # No pass 2 revocation needed: aliases are in a separate output field,
      # so alias cost doesn't affect code size. Pass 1's saved_per_use > 0
      # check is sufficient.
    end

    # Generate backward-compatible alias declarations for renamed constants.
    # Returns array of strings like "OriginalName=ShortName" or
    # "ShortParent::OriginalName=ShortParent::ShortName" for nested constants.
    def generate_alias_declarations
      renamed = @mappings.values.select(&:short_name).sort_by { |info| [info.full_path.size, info.full_path] }
      renamed.filter_map { |info| build_alias_declaration(info) }
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

    # Get usage count for a constant by static_cpath
    def usage_count_for_path(static_cpath)
      info = @mappings[static_cpath]
      info ? info.usage_count : 0
    end

    # Set usage count for a constant by static_cpath
    def set_usage_count_by_path(static_cpath, count)
      raise "Cannot set usage when finalized" if finalized?
      info = @mappings[static_cpath]
      info.usage_count = count if info
    end

    # Iterate over user-defined constant paths
    def each_user_defined_path(&block)
      @mappings.each_key(&block)
    end

    # Check if a path is a class or module definition
    def class_or_module_path?(static_cpath)
      info = @mappings[static_cpath]
      info && (info.definition_type == :class || info.definition_type == :module)
    end

    private

    # Check if a constant path already exists in the Ruby runtime.
    # Used to detect class/module reopenings (e.g., `class Array` adding methods
    # to a built-in class) which must not be renamed.
    def runtime_constant?(cpath)
      cpath.reduce(Object) do |mod, name|
        return false unless mod.is_a?(Module) && mod.const_defined?(name, false)
        mod.const_get(name, false)
      end
      true
    rescue
      false
    end

    # Build backward alias declaration for renamed value constants.
    # Class/module constants are never renamed (no short_name assigned).
    def build_alias_declaration(info)
      path = info.full_path
      # LHS: short parent path + original leaf name
      lhs = path.each_index.map { |i|
        if i < path.size - 1
          short_name_for_path(path[0..i]) || path[i].to_s
        else
          path[i].to_s
        end
      }.join('::')
      # RHS: full short path
      rhs = path.each_index.map { |i|
        short_name_for_path(path[0..i]) || path[i].to_s
      }.join('::')
      lhs == rhs ? nil : "#{lhs}=#{rhs}"
    end
  end

end

# frozen_string_literal: true

require 'set'

module RubyMinify
  # Represents an external library constant prefix that can be aliased
  ExternalPrefixInfo = Struct.new(
    :prefix_path,    # Array<Symbol> - Prefix path (e.g., [:TypeProf, :Core, :AST])
    :prefix_string,  # String - Full prefix string (e.g., "TypeProf::Core::AST")
    :short_name,     # String - Assigned short name (e.g., "Z")
    :usage_count,    # Integer - Number of references using this prefix
    :char_savings,   # Integer - Net character savings from aliasing
    keyword_init: true
  ) do
    def initialize(prefix_path: nil, prefix_string: nil, short_name: nil,
                   usage_count: nil, char_savings: nil)
      self.prefix_path = prefix_path || []
      self.prefix_string = prefix_string
      self.short_name = short_name
      self.usage_count = usage_count || 0
      self.char_savings = char_savings || 0
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
  # constants with same name in different modules.
  # Also tracks external prefix aliases (absorbed from ExternalPrefixAliaser).
  class ConstantRenameMapping
    MIN_PREFIX_SAVINGS_THRESHOLD = 10

    attr_reader :mappings, :used_short_names

    def initialize
      @mappings = {}           # Hash<Array<Symbol>, ConstantInfo> - key is static_cpath
      @by_name = {}            # Hash<Symbol, Array<ConstantInfo>> - lookup by simple name
      @used_short_names = Set.new
      @external_prefixes = {}  # Hash<Array<Symbol>, ExternalPrefixInfo> - external prefix mappings
      @prefix_counts = Hash.new(0) # Hash<Array<Symbol>, Integer> - raw prefix reference counts
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

    # Freeze the mapping and assign short names.
    # Unified allocation: internal constants and external prefixes are merged
    # into a single sorted list and allocated from the same NameGenerator.
    # This follows the src.dest two-phase model: propagation (this method)
    # determines ALL short names before any application.
    def assign_short_names(name_generator, skip_class_modules: false)
      raise "Already finalized" if finalized?

      @state = :frozen

      # Collect all existing constant names for collision checking
      existing_names = Set.new(@mappings.values.map { |info| info.original_name.to_s })

      # Build external prefix candidates with preamble-induced parent refs
      prefix_candidates = build_prefix_candidates

      # Build unified allocation list: [estimated_savings, :internal/:external, object]
      entries = []

      @mappings.each_value do |info|
        next if skip_class_modules && info.definition_type != :value
        next if info.definition_type != :value && runtime_constant?(info.full_path)
        savings = info.original_name.to_s.length * (info.usage_count + 1)
        entries << [savings, :internal, info]
      end

      prefix_candidates.each do |info|
        entries << [info.char_savings, :external, info]
      end

      # Sort by estimated savings descending
      entries.sort_by! { |e| -e[0] }

      # Allocate names in one pass
      candidate = nil
      entries.each do |_savings, kind, info|
        if candidate.nil?
          candidate = name_generator.next_name
          candidate = name_generator.next_name while existing_names.include?(candidate)
        end

        case kind
        when :internal
          original_len = info.original_name.to_s.length
          saved_per_use = original_len - candidate.length
          next unless saved_per_use > 0
          total_occurrences = info.usage_count + 1
          next unless saved_per_use * total_occurrences > 0
          info.short_name = candidate
          @used_short_names << candidate

        when :external
          actual_savings_per_use = info.prefix_string.length - candidate.length
          next unless actual_savings_per_use > 0
          actual_declaration_cost = candidate.length + 1 + info.prefix_string.length + 1
          actual_net_savings = (actual_savings_per_use * info.usage_count) - actual_declaration_cost
          next unless actual_net_savings > 0
          info.short_name = candidate
          info.char_savings = actual_net_savings
          existing_names << candidate
          @external_prefixes[info.prefix_path] = info
        end

        candidate = nil
      end
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

    # Add an external prefix reference count (e.g., [:TypeProf, :Core, :AST] with count 20)
    def add_external_prefix(prefix_path, usage_count:)
      raise "Cannot add external prefix when finalized" if finalized?
      @state = :collecting if empty?
      @prefix_counts[prefix_path] += usage_count
    end

    # Get short name for the prefix of a full external path
    def short_name_for_prefix(full_path)
      return nil if full_path.nil? || full_path.size < 2
      prefix = full_path[0...-1]
      info = @external_prefixes[prefix]
      info&.short_name
    end

    # Generate prefix declaration statements (e.g., ["Z=TypeProf::Core::AST"])
    # Uses chained aliases when a sub-prefix is also aliased
    def generate_prefix_declarations
      sorted = @external_prefixes.values.sort_by { |info| [info.prefix_path.size, -(info.char_savings || 0)] }

      alias_map = {}
      sorted.map do |info|
        decl_rhs = info.prefix_string
        (info.prefix_path.size - 1).downto(2) do |len|
          sub = info.prefix_path[0...len]
          if alias_map.key?(sub)
            remaining = info.prefix_path[len..].map(&:to_s).join('::')
            decl_rhs = "#{alias_map[sub]}::#{remaining}"
            break
          end
        end
        alias_map[info.prefix_path] = info.short_name
        "#{info.short_name}=#{decl_rhs}"
      end
    end

    private

    # Build external prefix candidates, including preamble-induced parent prefixes.
    # This pre-calculates ALL prefix references (code + preamble-induced) before
    # allocation, ensuring idempotent output by construction.
    def build_prefix_candidates
      # Calculate savings for each prefix
      all_prefixes = @prefix_counts.map do |prefix, count|
        prefix_string = prefix.map(&:to_s).join('::')
        savings_per_use = prefix_string.length - 1
        declaration_cost = 1 + 1 + prefix_string.length + 1
        net_savings = (savings_per_use * count) - declaration_cost

        ExternalPrefixInfo.new(
          prefix_path: prefix,
          prefix_string: prefix_string,
          usage_count: count,
          char_savings: net_savings
        )
      end

      # Filter to beneficial prefixes
      beneficial = all_prefixes.select { |info| info.char_savings >= MIN_PREFIX_SAVINGS_THRESHOLD }

      # Pre-calculate preamble-induced parent prefix references:
      # each beneficial prefix's declaration references its parent prefix
      parent_extra = Hash.new(0)
      beneficial.each do |info|
        next if info.prefix_path.size < 2
        parent = info.prefix_path[0...-1]
        parent_extra[parent] += 1
      end

      # Add parent prefixes that become beneficial with preamble-induced refs
      parent_extra.each do |parent, preamble_refs|
        next if beneficial.any? { |info| info.prefix_path == parent }
        code_refs = @prefix_counts[parent] || 0
        total = code_refs + preamble_refs

        parent_string = parent.map(&:to_s).join('::')
        optimistic_savings = (parent_string.length - 1) * total - (1 + 1 + parent_string.length + 1)
        next unless optimistic_savings >= MIN_PREFIX_SAVINGS_THRESHOLD

        beneficial << ExternalPrefixInfo.new(
          prefix_path: parent,
          prefix_string: parent_string,
          usage_count: total,
          char_savings: optimistic_savings
        )
      end

      beneficial
    end

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

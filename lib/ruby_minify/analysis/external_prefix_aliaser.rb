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

  # Tracks and aliases external library constant prefixes for compression
  # Example: TypeProf::Core::AST::CallNode -> Z::CallNode with Z=TypeProf::Core::AST
  class ExternalPrefixAliaser
    # Minimum character savings required to alias a prefix
    MIN_SAVINGS_THRESHOLD = 10

    attr_reader :mappings

    def initialize(user_defined_paths)
      @user_defined_paths = user_defined_paths
      @prefix_counts = Hash.new(0)  # Hash<Array<Symbol>, Integer>
      @mappings = {}                # Hash<Array<Symbol>, ExternalPrefixInfo>
      @state = :collecting
    end

    def finalized?
      @state == :frozen
    end

    # Collect a reference to an external constant
    # full_path is the complete path like [:TypeProf, :Core, :AST, :CallNode]
    def collect_reference(full_path)
      return if @user_defined_paths.include?(full_path)
      return if full_path.size < 2
      # Skip if any sub-prefix is user-defined (reference is internal, not external)
      (1...full_path.size).each { |i| return if @user_defined_paths.include?(full_path[0...i]) }

      # Extract prefix (everything except the last element)
      prefix = full_path[0...-1]
      @prefix_counts[prefix] += 1
    end

    # Freeze the mapping and assign short names to beneficial prefixes
    def assign_short_names(name_generator)
      raise 'Already finalized' if finalized?

      @state = :frozen

      # Collect existing constant names for collision checking
      existing_names = Set.new(@user_defined_paths.map { |path| path.last.to_s })

      # Calculate savings for each prefix
      all_prefixes = @prefix_counts.map do |prefix, count|
        prefix_string = prefix.map(&:to_s).join('::')
        # Savings per use: original prefix length minus 1 (for short name)
        # e.g., "TypeProf::Core::AST" (18 chars) -> "Z" (1 char) = 17 chars saved per use
        savings_per_use = prefix_string.length - 1
        # Declaration cost: short_name + "=" + prefix_string + ";"
        # e.g., "Z=TypeProf::Core::AST;" = 21 chars
        declaration_cost = 1 + 1 + prefix_string.length + 1
        net_savings = (savings_per_use * count) - declaration_cost

        ExternalPrefixInfo.new(
          prefix_path: prefix,
          prefix_string: prefix_string,
          usage_count: count,
          char_savings: net_savings
        )
      end

      # Filter to only beneficial prefixes
      beneficial_prefixes = all_prefixes.select { |info| info.char_savings >= MIN_SAVINGS_THRESHOLD }

      # Sort by net savings (descending) for optimal compression
      beneficial_prefixes.sort_by! { |info| -info.char_savings }

      # Assign short names, verifying actual savings with real candidate length
      beneficial_prefixes.each do |info|
        candidate = name_generator.next_name
        candidate = name_generator.next_name while existing_names.include?(candidate)

        # Recalculate with actual candidate length
        actual_savings_per_use = info.prefix_string.length - candidate.length
        next unless actual_savings_per_use > 0

        actual_declaration_cost = candidate.length + 1 + info.prefix_string.length + 1
        actual_net_savings = (actual_savings_per_use * info.usage_count) - actual_declaration_cost
        next unless actual_net_savings > 0

        info.short_name = candidate
        info.char_savings = actual_net_savings
        existing_names << candidate
        @mappings[info.prefix_path] = info
      end

      # No prediction of declaration-induced references needed:
      # prefix declarations are output as preamble (separate from code),
      # so re-minification never sees them as source references.
    end

    # Get short name for the prefix of a full path
    # Returns nil if the prefix is not aliased
    def short_name_for_prefix(full_path)
      return nil if full_path.nil? || full_path.size < 2

      prefix = full_path[0...-1]
      info = @mappings[prefix]
      info&.short_name
    end

    # Generate prefix declaration statements
    # Returns array like ["Z=TypeProf::Core::AST", ...]
    # Uses chained aliases when a sub-prefix is also aliased
    def generate_prefix_declarations
      sorted = @mappings.values.sort_by { |info| [info.prefix_path.size, -info.char_savings] }

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
  end
end

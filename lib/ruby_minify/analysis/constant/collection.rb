# frozen_string_literal: true

module RubyMinify
  def syntax_data(subnode)
    if subnode.respond_to?(:location)
      loc = subnode.location
      @syntax_data[[loc.start_line, loc.start_column]] || {}
    else
      cr = subnode.code_range
      @syntax_data[[cr.first.lineno, cr.first.column]] || {}
    end
  end

  # Normalize ConstantWriteNode's static_cpath to remove path doubling.
  # TypeProf produces scope + explicit_path for ConstantPathWriteNode (e.g., Foo::Bar::X inside
  # module Foo; module Bar gives [:Foo,:Bar,:Foo,:Bar,:X]). This strips the redundant scope prefix.
  def normalize_const_write_cpath(node)
    static_cpath = node.static_cpath
    explicit_len = syntax_data(node)[:cpath_write_segments]
    return static_cpath unless explicit_len

    scope_len = static_cpath.length - explicit_len
    return static_cpath if scope_len <= 0

    scope = static_cpath[0...scope_len]
    explicit_path = static_cpath[scope_len..]

    if explicit_path.length >= scope.length && explicit_path[0...scope.length] == scope
      scope + explicit_path[scope.length..]
    else
      static_cpath
    end
  end

  # Resolve a ConstantReadNode to its fully-qualified path using TypeProf's analysis result.
  # For class/module constants: static_ret.cpath provides the path directly.
  # For value constants (cpath=nil): derive path from cdef.defs[].static_cpath.
  # For qualified refs with cbase (Foo::CONST): derive from cbase.static_ret.cpath + cname.
  def resolve_constant_read_cpath(node)
    return nil unless node.is_a?(TypeProf::Core::AST::ConstantReadNode)

    static_ret = node.static_ret rescue nil
    return nil unless static_ret
    return nil unless static_ret.respond_to?(:cpath)

    # Class/module constants have cpath directly
    return static_ret.cpath if static_ret.cpath

    # Value constants: derive from cdef's definition node
    cdef = static_ret.respond_to?(:cdef) ? static_ret.cdef : nil
    if cdef&.respond_to?(:defs)
      cdef.defs.each do |d|
        return d.static_cpath if d.respond_to?(:static_cpath) && d.static_cpath
      end
    end

    # Qualified refs (Foo::CONST): derive from cbase chain
    if node.cbase
      cbase_cpath = resolve_constant_read_cpath(node.cbase)
      return cbase_cpath + [node.cname] if cbase_cpath
    end

    nil
  end

  def build_constant_path(node)
    return nil unless node.is_a?(TypeProf::Core::AST::ConstantReadNode)

    path = [node.cname]
    current = node.cbase
    while current
      if current.is_a?(TypeProf::Core::AST::ConstantReadNode)
        path.unshift(current.cname)
        current = current.cbase
      else
        break
      end
    end
    path
  end

  def resolve_constant_path(const_node, current_scope)
    return nil unless const_node.is_a?(TypeProf::Core::AST::ConstantReadNode)

    if const_node.cbase
      return build_constant_path(const_node)
    end

    simple_name = const_node.cname
    scope = current_scope.is_a?(Array) ? current_scope[0...-1] : []
    full_path = scope + [simple_name]
    return full_path if @constant_mapping&.user_defined_path?(full_path)

    nil
  end

  def exclude_private_constants(nodes)
    nodes.body.traverse do |event, node|
      next unless event == :enter
      next unless node.is_a?(TypeProf::Core::AST::CallNode)
      next unless %i[private_constant public_constant].include?(node.mid)
      cpath = node.lenv.cref.cpath
      node.positional_args&.each do |arg|
        next unless arg.is_a?(TypeProf::Core::AST::SymbolNode)
        @constant_mapping.exclude_path(cpath + [arg.lit])
      end
    end
  end

  def collect_constants(nodes)
    nodes.body.traverse do |event, node|
      next unless event == :enter
      case node
      when TypeProf::Core::AST::ClassNode
        @constant_mapping.add_definition_with_path(node.static_cpath, definition_type: :class)
      when TypeProf::Core::AST::ModuleNode
        @constant_mapping.add_definition_with_path(node.static_cpath, definition_type: :module)
      when TypeProf::Core::AST::ConstantWriteNode
        # Skip constants defined inside `class << self` — they live on the
        # metaclass and cannot be accessed as Foo::X, so alias declarations
        # would fail at runtime.
        next if node.lenv&.cref&.scope_level == :metaclass
        @constant_mapping.add_definition_with_path(normalize_const_write_cpath(node), definition_type: :value)
      end
    end
  end

  def count_constant_references(nodes)
    nodes.body.traverse do |event, node|
      next unless event == :enter
      case node
      when TypeProf::Core::AST::ClassNode, TypeProf::Core::AST::ModuleNode
        @constant_mapping.increment_usage_by_path(node.static_cpath)
      when TypeProf::Core::AST::ConstantReadNode
        increment_constant_read_usage(node)
      when TypeProf::Core::AST::ConstantWriteNode
        @constant_mapping.increment_usage_by_path(normalize_const_write_cpath(node))
      end
    end
  end

  def increment_constant_read_usage(node)
    user_path = resolve_user_defined_cpath(node)
    if user_path
      @constant_mapping.increment_usage_by_path(user_path)
    else
      @constant_mapping.increment_usage(node.cname)
    end
  end

  def resolve_user_defined_cpath(node)
    [resolve_constant_read_cpath(node), build_constant_path(node)].each do |cpath|
      return cpath if cpath && @constant_mapping.user_defined_path?(cpath)
    end
    nil
  end

  def augment_constant_counts_via_typeprof(genv)
    @constant_mapping.each_user_defined_path do |cpath|
      ve = genv.resolve_const(cpath) rescue nil
      next unless ve && ve.respond_to?(:read_boxes)
      typeprof_count = ve.read_boxes.size
      current_count = @constant_mapping.usage_count_for_path(cpath)
      if typeprof_count > current_count
        @constant_mapping.set_usage_count_by_path(cpath, typeprof_count)
      end
    end
  end

  def collect_external_references(nodes)
    cbase_ids = Set.new
    prefix_counts = Hash.new(0)

    nodes.body.traverse do |event, node|
      next unless event == :enter
      next unless node.is_a?(TypeProf::Core::AST::ConstantReadNode)
      next if cbase_ids.include?(node.object_id)

      # Mark cbase chain to avoid double-counting sub-paths
      current = node.cbase
      while current.is_a?(TypeProf::Core::AST::ConstantReadNode)
        cbase_ids << current.object_id
        current = current.cbase
      end

      full_path = build_constant_path(node)
      resolved_cpath = resolve_constant_read_cpath(node)
      is_user_defined = (full_path && @constant_mapping.user_defined_path?(full_path)) ||
                        (resolved_cpath && @constant_mapping.user_defined_path?(resolved_cpath))
      effective_path = resolved_cpath || full_path
      if effective_path && !is_user_defined
        next if effective_path.size < 2
        next if full_path && @constant_mapping.has_user_defined_prefix?(full_path)
        prefix = effective_path[0...-1]
        prefix_counts[prefix] += 1
      end
    end

    prefix_counts.each do |prefix, count|
      @constant_mapping.add_external_prefix(prefix, usage_count: count)
    end
  end
end

# frozen_string_literal: true

module RubyMinify
  def collect_keyword_info(nodes, genv)
    @keyword_def_node_registry = {}

    nodes.traverse do |event, node|
      next unless event == :enter && node.is_a?(TypeProf::Core::AST::DefNode)

      req_kw = node.req_keywords || []
      opt_kw = node.opt_keywords || []
      next if req_kw.empty? && opt_kw.empty?

      node.boxes(:mdef) do |box|
        method_key = [box.cpath, box.singleton, box.mid].freeze
        (req_kw + opt_kw).each { |sym| @keyword_rename_mapping.add_keyword_def(method_key, sym) }

        @keyword_def_node_registry[method_key] ||= []
        @keyword_def_node_registry[method_key] << node

        if node.rest_keywords
          @keyword_rename_mapping.exclude_method(method_key)
        end
      end
    end

    collect_keyword_call_sites(genv, nodes)
  end

  private

  def collect_keyword_call_sites(genv, nodes)
    call_node_to_keys = Hash.new { |h, k| h[k] = [] }
    super_merges = []
    zero_call_keys = []
    has_super_target = Set.new

    @keyword_rename_mapping.each_method_key do |key|
      method_entity = genv.resolve_method(key[0], key[1], key[2])
      next unless method_entity

      call_count = 0
      method_entity.method_call_boxes.each do |cb|
        cn = cb.node

        if cn.is_a?(TypeProf::Core::AST::SuperNode) ||
           cn.is_a?(TypeProf::Core::AST::ForwardingSuperNode)
          child_cpath = cn.lenv.cref.cpath
          child_key = [child_cpath, key[1], key[2]].freeze
          super_merges << [child_key, key]
          has_super_target << key
          next
        end

        call_count += 1

        kw_args = cn.respond_to?(:keyword_args) ? cn.keyword_args : nil
        next unless kw_args
        next unless kw_args.is_a?(TypeProf::Core::AST::HashNode)

        if kw_args.keys.any?(&:nil?)
          @keyword_rename_mapping.exclude_method(key)
          break
        end

        kw_args.keys.zip(kw_args.vals).each do |sym_node, val_node|
          next unless sym_node.is_a?(TypeProf::Core::AST::SymbolNode)
          @keyword_rename_mapping.add_keyword_call(key, sym_node.lit, sym_node, val_node)
        end

        call_node_to_keys[cn.object_id] << key
      end

      zero_call_keys << key if call_count == 0
    end

    super_merges.each do |child_key, parent_key|
      @keyword_rename_mapping.merge_groups(child_key, parent_key)
    end

    call_node_to_keys.each_value do |keys|
      next if keys.size < 2
      (1...keys.size).each { |i| @keyword_rename_mapping.merge_groups(keys[i - 1], keys[i]) }
    end

    zero_call_keys.each do |key|
      next if has_super_target.include?(key)
      @keyword_rename_mapping.exclude_method(key)
    end

    exclude_unresolved_keyword_calls(nodes, genv)
  end

  def exclude_unresolved_keyword_calls(nodes, genv)
    keyword_mids = Set.new
    @keyword_rename_mapping.each_method_key { |key| keyword_mids << key[2] }
    return if keyword_mids.empty?

    resolved_call_ids = Set.new
    @keyword_rename_mapping.each_method_key do |key|
      me = genv.resolve_method(key[0], key[1], key[2])
      next unless me
      me.method_call_boxes.each { |cb| resolved_call_ids << cb.node.object_id }
    end

    unresolved_mids = Set.new
    nodes.traverse do |event, node|
      next unless event == :enter
      next unless node.is_a?(TypeProf::Core::AST::CallNode)
      if keyword_mids.include?(node.mid) && !resolved_call_ids.include?(node.object_id)
        unresolved_mids << node.mid
      end
    end

    unresolved_mids.each do |mid|
      @keyword_rename_mapping.each_method_key do |key|
        @keyword_rename_mapping.exclude_method(key) if key[2] == mid
      end
    end
  end

  public
end

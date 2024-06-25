# frozen_string_literal: true

module RubyMinify
  def resolve_method_aliases_and_transforms(nodes, genv)
    alias_map = {}
    transform_map = {}
    nodes.traverse do |event, node|
      next unless event == :enter
      next unless node.is_a?(TypeProf::Core::AST::CallNode)

      shorter = METHOD_ALIASES[node.mid]
      if shorter
        if node.recv
          alias_map[location_key(node)] = shorter if alias_available_on_receiver?(node.recv, shorter, genv)
        else
          alias_map[location_key(node)] = shorter
        end
      end

      if node.recv && node.positional_args.empty?
        METHOD_TRANSFORMS.each do |(mid, type_name), replacement|
          next unless mid == node.mid
          if receiver_matches_type?(node.recv, type_name, genv)
            transform_map[location_key(node)] = replacement
            break
          end
        end
      end
    end
    [alias_map, transform_map]
  end

  private

  def alias_available_on_receiver?(recv_node, shorter_method, genv)
    return false unless recv_node.respond_to?(:ret) && recv_node.ret

    types = recv_node.ret.types
    return false if types.empty?

    types.all? do |ty, _|
      base = ty.base_type(genv)
      next false unless base.respond_to?(:mod)
      method_available_on_type?(genv, base.mod, base.is_a?(TypeProf::Core::Type::Singleton), shorter_method)
    end
  end

  def method_available_on_type?(genv, mod, singleton, method_name)
    genv.each_superclass(mod, singleton) do |ancestor_mod, s|
      me = ancestor_mod.methods[s]&.[](method_name)
      return true if me && (me.exist? || me.aliases.any?)
    end
    false
  end

  def receiver_matches_type?(recv_node, type_name, genv)
    return false unless recv_node.respond_to?(:ret) && recv_node.ret

    types = recv_node.ret.types
    return false if types.empty?

    target_mod = genv.resolve_cpath([type_name])
    return false unless target_mod

    types.all? do |ty, _|
      base = ty.base_type(genv)
      next false unless base.respond_to?(:mod)
      mod_is_or_inherits?(genv, base.mod, target_mod)
    end
  end

  def mod_is_or_inherits?(genv, mod, target)
    return true if mod == target
    genv.each_superclass(mod, false) do |ancestor, _|
      return true if ancestor == target
    end
    false
  end
end

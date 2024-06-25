# frozen_string_literal: true

module RubyMinify
  DYNAMIC_CVAR_METHODS = %i[
    class_variable_get class_variable_set
    class_variable_defined? class_variables
    remove_class_variable
  ].freeze

  def collect_cvar_definitions(nodes)
    nodes.traverse do |event, node|
      next unless event == :enter
      case node
      when TypeProf::Core::AST::ClassVariableReadNode
        cpath = node.lenv.cref.cpath
        @cvar_rename_mapping.add_read_site(cpath, node.var, node)
      when TypeProf::Core::AST::ClassVariableWriteNode
        cpath = node.lenv.cref.cpath
        @cvar_rename_mapping.add_write_site(cpath, node.var, node)
      end
    end
  end

  def scan_dynamic_cvar_access(nodes)
    nodes.traverse do |event, node|
      next unless event == :enter
      next unless node.is_a?(TypeProf::Core::AST::CallNode)
      next unless DYNAMIC_CVAR_METHODS.include?(node.mid)

      recv = node.recv
      if recv.nil? || recv.is_a?(TypeProf::Core::AST::SelfNode)
        cpath = node.lenv.cref.cpath
        @cvar_rename_mapping.exclude_cpath(cpath)
      end
    end
  end

  def merge_inherited_cvars(genv)
    cpaths = []
    @cvar_rename_mapping.each_canonical_cpath { |c| cpaths << c }
    cpaths.each do |cpath|
      mod = genv.resolve_cpath(cpath) rescue nil
      next unless mod
      genv.each_superclass(mod, false) do |ancestor_mod, _|
        next if ancestor_mod.cpath == cpath
        @cvar_rename_mapping.merge_with_ancestor(cpath, ancestor_mod.cpath)
      end
    end
  end
end

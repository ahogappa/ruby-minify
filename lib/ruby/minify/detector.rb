# frozen_string_literal: true

module Ruby
  module Minify
    # Detects dynamic code patterns that should disable variable mangling
    # to prevent runtime breakage (eval, binding, send, etc.)
    class Detector
      # Methods that can access variables by string/symbol name
      DYNAMIC_METHODS = %i[
        eval
        instance_eval
        class_eval
        module_eval
        binding
        local_variable_get
        local_variable_set
        send
        __send__
        public_send
        method
        define_method
        respond_to?
      ].freeze

      attr_reader :unsafe_scopes

      def initialize
        # Set of scope object_ids that contain dynamic patterns
        @unsafe_scopes = Set.new
      end

      # Scan AST nodes and collect scopes that contain dynamic patterns
      def scan(nodes)
        @current_scope_id = nil
        nodes.body.stmts.each { |stmt| scan_node(stmt) }
        self
      end

      private

      def scan_node(node)
        case node
        when TypeProf::Core::AST::DefNode
          # Enter method scope
          prev_scope = @current_scope_id
          @current_scope_id = node.object_id
          scan_node(node.body) if node.body
          @current_scope_id = prev_scope

        when TypeProf::Core::AST::ClassNode, TypeProf::Core::AST::ModuleNode
          scan_node(node.body) if node.body

        when TypeProf::Core::AST::CallNode
          # Check if this is a dynamic method call
          if DYNAMIC_METHODS.include?(node.mid)
            mark_current_scope_unsafe
          end

          # Scan receiver and arguments
          scan_node(node.recv) if node.recv
          node.positional_args.each { |arg| scan_node(arg) }

          # Handle blocks
          if node.block_body
            prev_scope = @current_scope_id
            @current_scope_id = node.object_id
            scan_node(node.block_body)
            @current_scope_id = prev_scope
          end

        when TypeProf::Core::AST::StatementsNode
          node.stmts.each { |stmt| scan_node(stmt) }

        when TypeProf::Core::AST::LocalVariableWriteNode
          scan_node(node.rhs) if node.rhs

        when TypeProf::Core::AST::IfNode, TypeProf::Core::AST::UnlessNode
          scan_node(node.cond)
          scan_node(node.then) if node.then
          scan_node(node.else) if node.else

        when TypeProf::Core::AST::AndNode, TypeProf::Core::AST::OrNode
          scan_node(node.e1)
          scan_node(node.e2)

        when TypeProf::Core::AST::ArrayNode
          node.elems.each { |elem| scan_node(elem) }

        when TypeProf::Core::AST::HashNode
          node.keys.each { |key| scan_node(key) }
          node.vals.each { |val| scan_node(val) }

        when TypeProf::Core::AST::ReturnNode
          scan_node(node.arg) if node.arg

        when TypeProf::Core::AST::CaseNode
          scan_node(node.pivot) if node.pivot
          node.when_nodes.each do |when_node|
            when_node.conditions.each { |cond| scan_node(cond) }
            scan_node(when_node.body) if when_node.body
          end
          scan_node(node.else_clause) if node.else_clause

        when TypeProf::Core::AST::InterpolatedStringNode, TypeProf::Core::AST::InterpolatedSymbolNode
          node.parts.each { |part| scan_node(part) }

        when TypeProf::Core::AST::WhileNode
          scan_node(node.cond)
          scan_node(node.body) if node.body

        when TypeProf::Core::AST::RangeNode
          scan_node(node.begin) if node.begin
          scan_node(node.end) if node.end

        when TypeProf::Core::AST::AttrReaderMetaNode,
             TypeProf::Core::AST::AttrAccessorMetaNode,
             TypeProf::Core::AST::IncludeMetaNode
          # These are meta nodes, no need to scan for dynamic patterns

        when TypeProf::Core::AST::YieldNode
          node.positional_args.each { |arg| scan_node(arg) }
        end
      end

      def mark_current_scope_unsafe
        @unsafe_scopes.add(@current_scope_id) if @current_scope_id
      end
    end
  end
end

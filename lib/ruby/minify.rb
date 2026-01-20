# frozen_string_literal: true

require 'typeprof'
require 'prism'
require_relative "minify/version"
require_relative "minify/name_generator"
require_relative "minify/detector"
require_relative "minify/method_aliases"

module Ruby
  module Minify
    class Error < StandardError; end
    class MinifyError < Error; end
    class SyntaxError < Error; end

    attr_reader :result

    def read_path(path)
      @path = path
      @file = File.read(path)
      @cache = SpecifyCache.new

      self
    end

    def minify(options = {})
      @options = options

      # Check for syntax errors using Prism
      prism_result = Prism.parse(@file)
      unless prism_result.errors.empty?
        error = prism_result.errors.first
        raise SyntaxError, "at #{@path}:#{error.location.start_line}:#{error.location.start_column}: #{error.message}"
      end

      nodes = TypeProf::Core::AST.parse_rb(@path, @file)

      if mangling_enabled?
        # Detect dynamic patterns (eval, send, binding, etc.)
        # that should disable mangling in their scope
        @detector = Detector.new.scan(nodes)

        # Build variable mappings using TypeProf's lenv.cref for scope identification
        # Key: lenv.cref.object_id => { original_var => mangled_name }
        @scope_mappings = {}
        build_scope_mappings(nodes)
      end

      # Rebuild with mangled names
      @result = rebuild(nodes).join(";")

      self
    end

    def mangling_enabled?
      @options.fetch(:mangle, true)
    end

    # Build scope mappings using TypeProf's lenv.cref for scope identification
    # Uses DefNode.tbl and CallNode.block_f_args to get variable lists
    def build_scope_mappings(nodes)
      nodes.body.stmts.each { |subnode| collect_scope_vars(subnode) }
    end

    def collect_scope_vars(node)
      case node
      when TypeProf::Core::AST::DefNode
        # Get cref_id from body's first statement (TypeProf's scope tracking)
        cref_id = get_body_cref_id(node.body)
        if cref_id && !@scope_mappings[cref_id]
          # Check if this scope contains dynamic patterns
          is_unsafe = scope_contains_dynamic_pattern?(node)

          generator = NameGenerator.new
          mapping = {}
          node.tbl.each do |var|
            mapping[var] = is_unsafe ? var.to_s : generator.next_name
          end
          @scope_mappings[cref_id] = mapping
        end
        collect_scope_vars(node.body) if node.body

      when TypeProf::Core::AST::ClassNode, TypeProf::Core::AST::ModuleNode
        collect_scope_vars(node.body) if node.body

      when TypeProf::Core::AST::CallNode
        collect_scope_vars(node.recv) if node.recv
        node.positional_args.each { |arg| collect_scope_vars(arg) }

        if node.block_body
          # Block creates a new scope - get cref_id from block body
          cref_id = get_body_cref_id(node.block_body)
          if cref_id && !@scope_mappings[cref_id]
            is_unsafe = block_contains_dynamic_pattern?(node)

            generator = NameGenerator.new
            mapping = {}
            # Register block parameters
            node.block_f_args.each do |param|
              mapping[param] = is_unsafe ? param.to_s : generator.next_name
            end
            @scope_mappings[cref_id] = mapping
          end
          collect_scope_vars(node.block_body)
        end

      when TypeProf::Core::AST::StatementsNode
        node.stmts.each { |stmt| collect_scope_vars(stmt) }

      when TypeProf::Core::AST::LocalVariableWriteNode
        collect_scope_vars(node.rhs) if node.rhs

      when TypeProf::Core::AST::IfNode, TypeProf::Core::AST::UnlessNode
        collect_scope_vars(node.cond)
        collect_scope_vars(node.then) if node.then
        collect_scope_vars(node.else) if node.else

      when TypeProf::Core::AST::WhileNode
        collect_scope_vars(node.cond)
        collect_scope_vars(node.body) if node.body

      when TypeProf::Core::AST::AndNode, TypeProf::Core::AST::OrNode
        collect_scope_vars(node.e1)
        collect_scope_vars(node.e2)

      when TypeProf::Core::AST::ArrayNode
        node.elems.each { |elem| collect_scope_vars(elem) }

      when TypeProf::Core::AST::HashNode
        node.keys.each { |key| collect_scope_vars(key) }
        node.vals.each { |val| collect_scope_vars(val) }

      when TypeProf::Core::AST::ReturnNode
        collect_scope_vars(node.arg) if node.arg

      when TypeProf::Core::AST::CaseNode
        collect_scope_vars(node.pivot) if node.pivot
        node.when_nodes.each do |when_node|
          when_node.conditions.each { |cond| collect_scope_vars(cond) }
          collect_scope_vars(when_node.body) if when_node.body
        end
        collect_scope_vars(node.else_clause) if node.else_clause

      when TypeProf::Core::AST::InterpolatedStringNode, TypeProf::Core::AST::InterpolatedSymbolNode
        node.parts.each { |part| collect_scope_vars(part) }
      end
    end

    # Get cref.object_id from the first statement in a body
    def get_body_cref_id(body)
      return nil unless body
      return nil if body.is_a?(TypeProf::Core::AST::DummyNilNode)

      first_node = find_first_lenv_node(body)
      first_node&.lenv&.cref&.object_id
    end

    # Find the first node that has lenv (for getting cref_id)
    def find_first_lenv_node(node)
      case node
      when TypeProf::Core::AST::StatementsNode
        node.stmts.each do |stmt|
          result = find_first_lenv_node(stmt)
          return result if result
        end
        nil
      when TypeProf::Core::AST::LocalVariableWriteNode,
           TypeProf::Core::AST::LocalVariableReadNode,
           TypeProf::Core::AST::CallNode,
           TypeProf::Core::AST::IfNode,
           TypeProf::Core::AST::UnlessNode,
           TypeProf::Core::AST::ReturnNode
        node
      when TypeProf::Core::AST::InterpolatedStringNode,
           TypeProf::Core::AST::InterpolatedSymbolNode
        # Look for nodes with lenv inside interpolated parts
        node.parts.each do |part|
          result = find_first_lenv_node(part)
          return result if result
        end
        nil
      when TypeProf::Core::AST::StringNode
        # StringNode has lenv
        node if node.respond_to?(:lenv) && node.lenv
      else
        nil
      end
    end

    # Check if DefNode scope contains dynamic patterns
    def scope_contains_dynamic_pattern?(def_node)
      check_dynamic_pattern(def_node.body)
    end

    # Check if block contains dynamic patterns
    def block_contains_dynamic_pattern?(call_node)
      check_dynamic_pattern(call_node.block_body)
    end

    # Check for dynamic patterns in AST subtree
    def check_dynamic_pattern(node)
      return false unless node

      case node
      when TypeProf::Core::AST::CallNode
        return true if Detector::DYNAMIC_METHODS.include?(node.mid)
        return true if check_dynamic_pattern(node.recv)
        return true if node.positional_args.any? { |arg| check_dynamic_pattern(arg) }
        return true if check_dynamic_pattern(node.block_body)
        false
      when TypeProf::Core::AST::StatementsNode
        node.stmts.any? { |stmt| check_dynamic_pattern(stmt) }
      when TypeProf::Core::AST::LocalVariableWriteNode
        check_dynamic_pattern(node.rhs)
      when TypeProf::Core::AST::IfNode, TypeProf::Core::AST::UnlessNode
        check_dynamic_pattern(node.cond) ||
          check_dynamic_pattern(node.then) ||
          check_dynamic_pattern(node.else)
      when TypeProf::Core::AST::WhileNode
        check_dynamic_pattern(node.cond) || check_dynamic_pattern(node.body)
      when TypeProf::Core::AST::AndNode, TypeProf::Core::AST::OrNode
        check_dynamic_pattern(node.e1) || check_dynamic_pattern(node.e2)
      when TypeProf::Core::AST::ArrayNode
        node.elems.any? { |elem| check_dynamic_pattern(elem) }
      when TypeProf::Core::AST::HashNode
        node.keys.any? { |key| check_dynamic_pattern(key) } ||
          node.vals.any? { |val| check_dynamic_pattern(val) }
      when TypeProf::Core::AST::ReturnNode
        check_dynamic_pattern(node.arg)
      else
        false
      end
    end

    # Get mangled name using TypeProf's lenv.cref for scope lookup
    def get_mangled_name(node, var)
      return var.to_s unless mangling_enabled?

      # Use TypeProf's lenv.cref to identify the scope
      cref = node.lenv&.cref
      return var.to_s unless cref

      # Look up in current scope and parent scopes
      current_cref = cref
      while current_cref
        cref_id = current_cref.object_id
        mapping = @scope_mappings[cref_id]
        return mapping[var] if mapping && mapping[var]
        current_cref = current_cref.outer
      end

      # Fallback to original name if not found
      var.to_s
    end

    def rebuild(nodes)
      nodes.body.stmts.map do |subnode|
        rebuild_node(subnode)
      end.reject(&:empty?)
    end

    def rebuild_node(subnode)
      case subnode
      when TypeProf::Core::AST::CallNode
        # Get potentially shortened method name
        method_name = transform_method_name(subnode)
        if middle_method?(subnode.mid)
          "#{rebuild_node(subnode.recv)}#{subnode.mid}#{rebuild_node(subnode.positional_args.first)}"
        elsif with_block_method?(subnode)
          if !subnode.block_body.nil?
            first_body_node = find_first_lenv_node(subnode.block_body)
            # Check if block uses numbered parameters (_1, _2, etc.) - these must remain implicit
            uses_numbered_params = subnode.block_f_args.any? { |p| p.to_s.match?(/^_\d+$/) }
            block_params_str = if uses_numbered_params
              ""
            else
              mangled_block_params = subnode.block_f_args.map do |param|
                first_body_node ? get_mangled_name(first_body_node, param) : param.to_s
              end
              "|#{mangled_block_params.join(',')}|"
            end
            block_body = rebuild_statement(subnode.block_body)
            "#{subnode.recv.nil? ? '' : "#{rebuild_node(subnode.recv)}."}#{method_name}#{subnode.positional_args.empty? ? '' : "(#{subnode.positional_args.map{rebuild_node(_1)}.join(',')})"}{#{block_params_str}#{block_body}}"
          elsif !subnode.block_pass.nil?
            "#{subnode.recv.nil? ? '' : "#{rebuild_node(subnode.recv)}."}#{method_name}#{subnode.positional_args.empty? ? '' : "(#{subnode.positional_args.map{rebuild_node(_1)}.join(',')})"}(&#{rebuild_node(subnode.block_pass)})"
          end
        elsif subnode.mid == '[]'.to_sym
          "#{rebuild_node(subnode.recv)}[#{subnode.positional_args.map{rebuild_node(_1)}.join(',')}]"
        elsif subnode.mid == '[]='.to_sym
          "#{rebuild_node(subnode.recv)}[#{rebuild_node(subnode.positional_args.first)}]=#{subnode.positional_args[1..].map{rebuild_node(_1)}.join}"
        elsif subnode.mid == '!'.to_sym
          "!#{rebuild_node(subnode.recv)}"
        else
          "#{subnode.recv.nil? ? '' : "#{rebuild_node(subnode.recv)}."}#{method_name}#{subnode.positional_args.empty? ? '' : "(#{subnode.positional_args.map{rebuild_node(_1)}.join(',')})"}"
        end
      when TypeProf::Core::AST::DefNode
        # Get mangled params using TypeProf's lenv.cref
        first_body_node = find_first_lenv_node(subnode.body)
        # Build required parameters
        mangled_req_params = subnode.req_positionals.map do |param|
          if first_body_node
            get_mangled_name(first_body_node, param)
          else
            param.to_s
          end
        end
        # Build optional parameters with defaults
        mangled_opt_params = subnode.opt_positionals.zip(subnode.opt_positional_defaults).map do |param, default|
          param_name = if first_body_node
            get_mangled_name(first_body_node, param)
          else
            param.to_s
          end
          "#{param_name}=#{rebuild_node(default)}"
        end
        all_params = mangled_req_params + mangled_opt_params
        body = rebuild_statement(subnode.body)
        body_str = body.nil? || body.empty? ? "" : ";#{body}"
        if all_params.empty?
          "def #{subnode.mid}#{body_str};end"
        else
          "def #{subnode.mid}(#{all_params.join(',')})#{body_str};end"
        end
      when TypeProf::Core::AST::YieldNode
        "yield #{subnode.positional_args.map{rebuild_node(_1)}.join(',')}"
      when TypeProf::Core::AST::IfNode
        then_body = rebuild_statement(subnode.then)
        else_body = rebuild_statement(subnode.else)
        # Check if bodies have multiple statements, return statements, or are complex
        then_multi = then_body && (then_body.include?(';') || then_body.start_with?('return'))
        else_multi = else_body && (else_body.include?(';') || else_body.start_with?('return'))
        if subnode.else.nil?
          if then_multi
            "if #{rebuild_node(subnode.cond)} then;#{then_body};end"
          else
            "#{then_body} if #{rebuild_node(subnode.cond)}"
          end
        elsif then_multi || else_multi
          then_str = then_body.nil? || then_body.empty? ? "" : ";#{then_body}"
          else_str = else_body.nil? || else_body.empty? ? "" : ";#{else_body}"
          "if #{rebuild_node(subnode.cond)} then#{then_str};else#{else_str};end"
        else
          # Add space after : to avoid symbol interpretation
          "#{rebuild_node(subnode.cond)} ? #{then_body}: #{else_body}"
        end
      when TypeProf::Core::AST::UnlessNode
        then_body = rebuild_statement(subnode.then)
        else_body = rebuild_statement(subnode.else)
        then_multi = then_body && (then_body.include?(';') || then_body.start_with?('return'))
        else_multi = else_body && (else_body.include?(';') || else_body.start_with?('return'))
        if subnode.else.nil?
          if then_multi
            "unless #{rebuild_node(subnode.cond)} then;#{then_body};end"
          else
            # Use unless statement modifier form
            "#{then_body} unless #{rebuild_node(subnode.cond)}"
          end
        elsif then_multi || else_multi
          then_str = then_body.nil? || then_body.empty? ? "" : ";#{then_body}"
          else_str = else_body.nil? || else_body.empty? ? "" : ";#{else_body}"
          "unless #{rebuild_node(subnode.cond)} then#{then_str};else#{else_str};end"
        else
          "!(#{rebuild_node(subnode.cond)}) ? #{then_body}: #{else_body}"
        end
      when TypeProf::Core::AST::WhileNode
        body = rebuild_statement(subnode.body)
        body_str = body.nil? || body.empty? ? "" : ";#{body}"
        "while #{rebuild_node(subnode.cond)}#{body_str};end"
      when TypeProf::Core::AST::CaseNode
        body = "case #{rebuild_node(subnode.pivot)};" + subnode.when_nodes.map do |when_node|
          conditions = when_node.conditions.map { |c| rebuild_node(c) }.join(',')
          clause_body = rebuild_statement(when_node.body)
          clause_str = clause_body.nil? || clause_body.empty? ? "" : ";#{clause_body}"
          "when #{conditions}#{clause_str}"
        end.join(";")
        if !subnode.else_clause.nil?
          else_body = rebuild_statement(subnode.else_clause)
          else_str = else_body.nil? || else_body.empty? ? "" : ";#{else_body}"
          body += ";else#{else_str}"
        end
        body += ";end"
      when TypeProf::Core::AST::ReturnNode
        case subnode.arg
        when TypeProf::Core::AST::DummyNilNode
          'return'
        else
          "return #{rebuild_node(subnode.arg)}"
        end
      when TypeProf::Core::AST::TrueNode
        '!!1'
      when TypeProf::Core::AST::FalseNode
        '!1'
      when TypeProf::Core::AST::OperatorNode
        # TODO
      when TypeProf::Core::AST::ClassNode
        body = rebuild_statement(subnode.body)
        body_str = body.nil? || body.empty? ? "" : ";#{body}"
        "class #{subnode.cpath.cname}#{subnode.superclass_cpath ? "<#{subnode.superclass_cpath.cname}" : ''}#{body_str};end"
      when TypeProf::Core::AST::ModuleNode
        body = rebuild_statement(subnode.body)
        body_str = body.nil? || body.empty? ? "" : ";#{body}"
        "module #{subnode.cpath.cname}#{body_str};end"
      when TypeProf::Core::AST::SelfNode
        'self'
      when TypeProf::Core::AST::AndNode
        "#{rebuild_node(subnode.e1)}&&#{rebuild_node(subnode.e2)}"
      when TypeProf::Core::AST::OrNode
        "#{rebuild_node(subnode.e1)}||#{rebuild_node(subnode.e2)}"
      when TypeProf::Core::AST::LocalVariableReadNode
        get_mangled_name(subnode, subnode.var)
      when TypeProf::Core::AST::LocalVariableWriteNode
        var_name = get_mangled_name(subnode, subnode.var)
        if self_assginment?(subnode)
          case subnode.rhs
          when TypeProf::Core::AST::OperatorNode
            "#{var_name}#{subnode.rhs.mid}=#{subnode.rhs.positional_args.map{rebuild_node(_1)}.join}"
          when TypeProf::Core::AST::OrNode
            "#{var_name}||=#{rebuild_node(subnode.rhs.e2)}"
          when TypeProf::Core::AST::AndNode
            "#{var_name}&&=#{rebuild_node(subnode.rhs.e2)}"
          end
        else
          "#{var_name}=#{rebuild_node(subnode.rhs)}"
        end
      when TypeProf::Core::AST::InstanceVariableReadNode
        subnode.var.to_s
      when TypeProf::Core::AST::InstanceVariableWriteNode
        if self_assginment?(subnode)
          case subnode.rhs
          when TypeProf::Core::AST::OperatorNode
            "#{subnode.var}#{subnode.rhs.mid}=#{subnode.rhs.positional_args.map{rebuild_node(_1)}.join}"
          when TypeProf::Core::AST::OrNode
            "#{subnode.var}||=#{rebuild_node(subnode.rhs.e2)}"
          when TypeProf::Core::AST::AndNode
            "#{subnode.var}&&=#{rebuild_node(subnode.rhs.e2)}"
          end
        else
          "#{subnode.var}=#{rebuild_node(subnode.rhs)}"
        end
      when TypeProf::Core::AST::ConstantReadNode
        "#{subnode.cbase.nil? ? '' : "#{rebuild_node(subnode.cbase)}::"}#{subnode.cname.to_s}"
      when TypeProf::Core::AST::ConstantWriteNode
        "#{subnode.static_cpath.join('::')}=#{rebuild_node(subnode.rhs)}"
      when TypeProf::Core::AST::StringNode
        # lit contains the source escape sequences, just wrap in quotes
        "\"#{subnode.lit}\""
      when TypeProf::Core::AST::IntegerNode
        subnode.lit.to_s
      when TypeProf::Core::AST::FloatNode
        subnode.lit.to_s
      when TypeProf::Core::AST::ArrayNode
        "[#{subnode.elems.map{rebuild_node(_1)}.join(',')}]"
      when TypeProf::Core::AST::RangeNode
        # Get exclude_end from raw Prism node
        raw_node = subnode.instance_variable_get(:@raw_node)
        exclude_end = raw_node&.exclude_end?
        operator = exclude_end ? '...' : '..'
        # Wrap in parentheses to ensure correct precedence (e.g., (1..10).to_a)
        "(#{rebuild_node(subnode.begin)}#{operator}#{rebuild_node(subnode.end)})"
      when TypeProf::Core::AST::SymbolNode
        ":#{subnode.lit}"
      when TypeProf::Core::AST::HashNode
        "{" + subnode.keys.zip(subnode.vals).map do |key, val|
          key_str = rebuild_node(key)
          # Symbol keys ending with ? or ! need space before => to avoid syntax errors
          # e.g., :has_key?=> is invalid, but :has_key? => is valid
          separator = (key.is_a?(TypeProf::Core::AST::SymbolNode) && key.lit.to_s.end_with?('?', '!')) ? ' =>' : '=>'
          "#{key_str}#{separator}#{rebuild_node(val)}"
        end.join(',') + "}"
      when TypeProf::Core::AST::InterpolatedStringNode
        "\"" + subnode.parts.map do |part|
          case part
          when TypeProf::Core::AST::StringNode
            # lit already contains source escape sequences, use directly
            part.lit
          else
            "\#{#{rebuild_statement(part)}}"
          end
        end.join + "\""
      when TypeProf::Core::AST::InterpolatedSymbolNode
        ":\"" + subnode.parts.map do |part|
          case part
          when TypeProf::Core::AST::StringNode
            # lit already contains source escape sequences, use directly
            part.lit
          else
            "\#{#{rebuild_statement(part)}}"
          end
        end.join + "\""
      when TypeProf::Core::AST::IncludeMetaNode
        "include #{rebuild_node(subnode.args.first)}"
      when TypeProf::Core::AST::AttrReaderMetaNode
        "attr #{subnode.args.map { |a| ":#{a}" }.join(',')}"
      when TypeProf::Core::AST::AttrAccessorMetaNode
        "attr_accessor #{subnode.args.map { |a| ":#{a}" }.join(',')}"
      when TypeProf::Core::AST::RegexpNode
        # Get the raw Prism node to extract regex content and flags
        raw_node = subnode.instance_variable_get(:@raw_node)
        content = raw_node.content
        # Build regex literal
        "/#{content}/"
      when TypeProf::Core::AST::DummyNilNode
        ''
      when TypeProf::Core::AST::NilNode
        '()'
      when TypeProf::Core::AST::StatementsNode
        rebuild_statement(subnode)
      else
        raise MinifyError, "Unknown node: #{subnode.class}"
      end
    end

    def rebuild_statement(nodes)
      return if nodes.is_a?(TypeProf::Core::AST::DummyNilNode)
      return '' if nodes.nil?

      # Handle StatementsNode vs single node
      if nodes.is_a?(TypeProf::Core::AST::StatementsNode)
        nodes.stmts.map do |subnode|
          rebuild_node(subnode)
        end.reject { |s| s.nil? || s.empty? }.join(";")
      else
        # Single node (not wrapped in StatementsNode)
        result = rebuild_node(nodes)
        result.nil? || result.empty? ? '' : result
      end
    end

    def middle_method?(method)
      %i[+ - * / ** % ^ > < <= >= <=> == ===].include?(method)
    end

    def need_quate?(node)
      %w[+ - / * % ^ & == === \\]
    end

    def self_assginment?(node)
      case node.rhs
      when TypeProf::Core::AST::OperatorNode
        node.var == node.rhs.recv.var
      when TypeProf::Core::AST::OrNode
        node.rhs.e1.var == node.var
      when TypeProf::Core::AST::AndNode
        node.rhs.e1.var == node.var
      else
        false
      end
    end

    def with_block_method?(node)
      !(node.block_body.nil? && node.block_pass.nil?)
    end

    # Check if transform option is enabled (default: true)
    def transform_enabled?
      @options.fetch(:transform, true)
    end

    # Get receiver type from AST node for method alias replacement
    # Returns class symbol (:Array, :Hash, etc.) or :unknown
    def get_receiver_type(recv_node)
      return :unknown unless recv_node

      # Handle StatementsNode wrapper (e.g., from parenthesized expressions like (-5))
      if recv_node.is_a?(TypeProf::Core::AST::StatementsNode) && recv_node.stmts.size == 1
        return get_receiver_type(recv_node.stmts.first)
      end

      # Handle method chaining: for CallNode, infer return type from receiver's type
      # Methods like select/find_all/collect on Array return Array
      if recv_node.is_a?(TypeProf::Core::AST::CallNode)
        receiver_type = get_receiver_type(recv_node.recv)
        method_name = recv_node.mid

        # Enumerable methods that return Array
        array_returning_methods = [:select, :find_all, :collect, :map, :reject,
                                   :sort, :sort_by, :take, :drop, :flatten,
                                   :compact, :uniq, :reverse, :shuffle, :sample,
                                   :flat_map, :collect_concat, :grep, :zip]
        if array_returning_methods.include?(method_name) && ENUMERABLE_CLASSES.include?(receiver_type)
          return :Array
        end

        # Hash methods that return Hash
        hash_returning_methods = [:select, :reject, :transform_keys, :transform_values,
                                  :merge, :compact, :invert, :slice, :except]
        if hash_returning_methods.include?(method_name) && receiver_type == :Hash
          return :Hash
        end

        # String methods that return String
        string_returning_methods = [:upcase, :downcase, :capitalize, :reverse,
                                    :strip, :chomp, :chop, :sub, :gsub, :tr]
        if string_returning_methods.include?(method_name) && receiver_type == :String
          return :String
        end

        return receiver_type if receiver_type != :unknown
        return :unknown
      end

      AST_TO_CLASS[recv_node.class] || :unknown
    end

    # Check if receiver type supports the alias replacement
    # Handles Enumerable inheritance for Array, Hash, Range, etc.
    def type_supports_alias?(receiver_type, alias_classes)
      return false if receiver_type == :unknown

      # Direct class match
      return true if alias_classes.include?(receiver_type)

      # Enumerable inheritance: if alias is for Enumerable, check if type is Enumerable
      if alias_classes.include?(:Enumerable) && ENUMERABLE_CLASSES.include?(receiver_type)
        return true
      end

      # Object methods apply to all classes
      return true if alias_classes.include?(:Object)

      # Numeric inheritance: Integer and Float are Numeric
      if alias_classes.include?(:Numeric) && [:Integer, :Float].include?(receiver_type)
        return true
      end

      false
    end

    # Transform method name to shorter alias if applicable
    # Returns shorter alias or original method name
    def transform_method_name(node)
      method_name = node.mid
      return method_name unless transform_enabled?

      alias_info = METHOD_ALIASES[method_name]
      return method_name unless alias_info

      receiver_type = get_receiver_type(node.recv)
      return method_name unless type_supports_alias?(receiver_type, alias_info[:classes])

      alias_info[:shorter]
    end

    def output(path = @path)
      File.write("./#{File.basename(path, '.rb')}.min.rb", @result)
    end
  end
end

class BaseMinify
  include Ruby::Minify
end

class SpecifyCache
  DEFAULT_CACHING_HASH = {
    :Kernel => {
      :p => 'p',
    },
    :Object => {
      :dup => 'dup',
    }
  }

  def initialize
    @cache = DEFAULT_CACHING_HASH
  end

  def set(key, value)
    @cache ||= {}
    @cache[key] = value
  end

  def get(key)
    @cache[key]
  end
end

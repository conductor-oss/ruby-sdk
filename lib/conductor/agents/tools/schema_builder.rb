# frozen_string_literal: true

module Conductor
  module Agents
    module Tools
      # Builds a JSON schema for a tool method from its keyword arguments.
      #
      # Ruby exposes keyword names and whether they are required (+Method#parameters+) but
      # never the default expressions, and the Tools DSL uses the default as the type:
      #
      #   tool def get_weather(city: String, units: 'metric', limit: 10, tags: [String], mode: %w[a b])
      #
      # so the defaults are read from the method's AST (RubyVM::AbstractSyntaxTree.of). That
      # works on MRI whenever the method's source file is on disk (and for eval'd code on
      # Ruby >= 3.2 with RubyVM.keep_script_lines = true). When the AST is unavailable the
      # builder falls back to Python's behaviour: every keyword becomes an untyped property
      # ({}), required when the keyword has no default.
      module SchemaBuilder # rubocop:disable Metrics/ModuleLength
        CLASS_TYPES = {
          'String' => 'string', 'Symbol' => 'string',
          'Integer' => 'integer',
          'Float' => 'number', 'Numeric' => 'number', 'BigDecimal' => 'number',
          'TrueClass' => 'boolean', 'FalseClass' => 'boolean',
          'Hash' => 'object', 'Array' => 'array',
          'Time' => 'string', 'Date' => 'string', 'DateTime' => 'string'
        }.freeze

        POSITIONAL = %i[req opt rest].freeze

        module_function

        # @param method [Method, UnboundMethod]
        # @return [Hash] JSON schema for the tool input
        def input_schema(method)
          params = method.parameters
          positional = params.select { |kind, _| POSITIONAL.include?(kind) }
          unless positional.empty?
            raise ConfigurationError,
                  "tool #{method.name}: use keyword arguments only (found positional #{positional.map(&:last).inspect})"
          end

          defaults = keyword_defaults(method)
          properties = {}
          required = []

          params.each do |kind, name|
            case kind
            when :keyreq
              properties[name.to_s] = defaults.key?(name) ? schema_for(defaults[name]) : {}
              required << name.to_s
            when :key
              if defaults.key?(name)
                schema, is_required = schema_for_default(defaults[name])
                properties[name.to_s] = schema
                required << name.to_s if is_required
              else
                properties[name.to_s] = {}
              end
            end
          end

          schema = { 'type' => 'object', 'properties' => properties }
          schema['required'] = required unless required.empty?
          schema
        end

        # Default output schema for worker tools: Dispatch always returns a JSON object
        def default_output_schema
          { 'type' => 'object', 'additionalProperties' => {} }
        end

        # Map keyword name => default AST node, or {} when no AST is available
        def keyword_defaults(method)
          ast = ast_of(method)
          return {} unless ast

          args = find_node(ast, :ARGS)
          return {} unless args

          kw = args.children[7]
          result = {}
          each_node(kw) do |node|
            next unless node.type == :KW_ARG

            lasgn = node.children[0]
            next unless lasgn.respond_to?(:type) && lasgn.type == :LASGN

            name, default = lasgn.children
            # required keywords (city:) carry a Symbol placeholder instead of a default node
            result[name] = default if default.is_a?(RubyVM::AbstractSyntaxTree::Node)
          end
          result
        end

        def ast_of(method)
          return nil unless defined?(RubyVM::AbstractSyntaxTree)

          RubyVM::AbstractSyntaxTree.of(method)
        rescue StandardError
          nil
        end

        # Schema for a default that stands for a *type* (class constant or array of one)
        def schema_for(node)
          schema_for_default(node).first
        end

        # @return [Array(Hash, Boolean)] schema and whether the parameter is required
        def schema_for_default(node)
          case node.type
          when :CONST
            type = CLASS_TYPES[node.children[0].to_s]
            [type ? { 'type' => type } : {}, true]
          when :COLON2
            type = CLASS_TYPES[node.children[1].to_s]
            [type ? { 'type' => type } : {}, true]
          when :STR
            [{ 'type' => 'string', 'default' => node.children[0] }, false]
          when :DSTR, :XSTR, :DXSTR
            [{ 'type' => 'string' }, false]
          when :LIT, :INTEGER, :FLOAT, :RATIONAL, :IMAGINARY
            literal_schema(node.children[0])
          when :TRUE
            [{ 'type' => 'boolean', 'default' => true }, false]
          when :FALSE
            [{ 'type' => 'boolean', 'default' => false }, false]
          when :NIL
            [{}, false]
          when :LIST, :ZLIST
            list_schema(node)
          when :HASH
            [{ 'type' => 'object', 'default' => {} }, false]
          else
            [{}, false]
          end
        end

        def literal_schema(value)
          case value
          when Integer then [{ 'type' => 'integer', 'default' => value }, false]
          when Float then [{ 'type' => 'number', 'default' => value }, false]
          when Symbol then [{ 'type' => 'string', 'default' => value.to_s }, false]
          when Regexp then [{ 'type' => 'string', 'pattern' => value.source }, false]
          else [{}, false]
          end
        end

        def list_schema(node)
          elements = node.type == :ZLIST ? [] : node.children.compact
          return [{ 'type' => 'array', 'default' => [] }, false] if elements.empty?

          if elements.size == 1 && %i[CONST COLON2].include?(elements[0].type)
            item, = schema_for_default(elements[0])
            return [{ 'type' => 'array', 'items' => item }, true]
          end

          if elements.all? { |e| e.type == :STR }
            values = elements.map { |e| e.children[0] }
            return [{ 'type' => 'string', 'enum' => values, 'default' => values.first }, false]
          end

          if elements.all? { |e| %i[LIT INTEGER].include?(e.type) && e.children[0].is_a?(Integer) }
            values = elements.map { |e| e.children[0] }
            return [{ 'type' => 'integer', 'enum' => values, 'default' => values.first }, false]
          end

          [{ 'type' => 'array' }, false]
        end

        def find_node(node, type)
          found = nil
          each_node(node) do |n|
            if n.type == type
              found = n
              break
            end
          end
          found
        end

        def each_node(node, &block)
          return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)

          block.call(node)
          node.children.each { |child| each_node(child, &block) }
        end
      end
    end
  end
end

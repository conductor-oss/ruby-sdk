# frozen_string_literal: true

module Conductor
  module Agents
    module Tools
      # Finds the secret names a tool body reads, so they can be declared on the wire
      # (TaskDef#runtime_metadata / tool.config.credentials) without a separate list.
      #
      # Only string literals are picked up:
      #
      #   secret('GH_TOKEN')            # => GH_TOKEN
      #   secrets_env('A', 'B')         # => A, B
      #   secret(name)                  # dynamic: declare with add_tool ..., credentials: [...]
      module SecretScanner
        SECRET_METHODS = %i[secret secrets_env].freeze

        module_function

        # @param method [Method, UnboundMethod]
        # @return [Array<String>] literal secret names, in order of appearance
        def scan(method)
          ast = SchemaBuilder.ast_of(method)
          return [] unless ast

          names = []
          SchemaBuilder.each_node(ast) do |node|
            method_id, args = call_parts(node)
            next unless SECRET_METHODS.include?(method_id)

            SchemaBuilder.each_node(args) { |a| names << a.children[0] if a.type == :STR }
          end
          names.uniq
        end

        def call_parts(node)
          case node.type
          when :FCALL then [node.children[0], node.children[1]]
          when :CALL, :QCALL then [node.children[1], node.children[2]]
          else [nil, nil]
          end
        end
      end
    end
  end
end

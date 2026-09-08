# frozen_string_literal: true

module Conductor
  module Agents
    module Tools
      # Adapts a RubyLLM::Tool class to a ToolDef so it can be given to an Agent as-is.
      #
      # RubyLLM exposes +name+, +description+ and +parameters+ (name => Parameter with
      # +type+, +description+, +required+) and executes via +#execute(**args)+. RubyLLM is an
      # optional dependency: this adapter only engages when RubyLLM::Tool is defined.
      module RubyLlmAdapter
        module_function

        # @return [Boolean] true when +klass+ is a RubyLLM::Tool subclass
        def ruby_llm_tool?(klass)
          return false unless defined?(::RubyLLM::Tool)

          klass.is_a?(Class) && klass < ::RubyLLM::Tool
        end

        # @param klass [Class] a RubyLLM::Tool subclass
        # @return [ToolDef]
        def to_tool_def(klass)
          instance = klass.new
          name = read(klass, instance, :name) || snake_case(klass.name.to_s.split('::').last)
          description = read(klass, instance, :description) || ''
          params = read(klass, instance, :parameters) || {}

          properties = {}
          required = []
          params.each do |param_name, param|
            schema = { 'type' => (fetch(param, :type) || 'string').to_s }
            desc = fetch(param, :description)
            schema['description'] = desc if desc
            properties[param_name.to_s] = schema
            required << param_name.to_s if fetch(param, :required) != false
          end

          input_schema = { 'type' => 'object', 'properties' => properties }
          input_schema['required'] = required unless required.empty?

          ToolDef.new(
            name: name.to_s,
            description: description.to_s,
            input_schema: input_schema,
            output_schema: SchemaBuilder.default_output_schema,
            func: ->(**args) { instance.execute(**args) }
          )
        end

        def read(klass, instance, attr)
          if klass.respond_to?(attr)
            klass.public_send(attr)
          elsif instance.respond_to?(attr)
            instance.public_send(attr)
          end
        end

        def fetch(param, key)
          if param.respond_to?(key)
            param.public_send(key)
          elsif param.respond_to?(:[])
            param[key] || param[key.to_s]
          end
        end

        def snake_case(name)
          name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end
      end
    end
  end
end

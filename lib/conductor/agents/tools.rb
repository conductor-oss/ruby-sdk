# frozen_string_literal: true

require_relative 'errors'
require_relative 'runtime/secrets'
require_relative 'tool_def'
require_relative 'tools/schema_builder'
require_relative 'tools/secret_scanner'
require_relative 'tools/ruby_llm_adapter'

module Conductor
  module Agents
    # The tool DSL.
    #
    #   include Conductor::Agents          # top level, or
    #   module Weather; extend Conductor::Agents::Tools; ... end
    #
    #   tool def get_weather(city: String, units: 'metric')
    #     { temp_c: 21.0 }
    #   end
    #   describe :get_weather, 'Get the current weather for a city.'
    #   requires_approval :get_weather
    #
    # +tool+ receives the Symbol that +def+ returns, builds a ToolDef from the method
    # (schema from keyword defaults, secrets from literal secret() calls) and registers it
    # both on the receiver (Weather[:get_weather], Weather.tool_defs) and in the global
    # registry that Agent#add_tool(:get_weather) consults.
    module Tools
      TOOL_OPTIONS = %i[description input_schema output_schema approval_required timeout_seconds credentials
                        stateful max_calls retry_count retry_delay_seconds retry_policy external].freeze

      # Weather[:current] on a module that `extend Conductor::Agents::Tools`
      module Lookup
        # @return [ToolDef]
        def [](name)
          fetch_tool(name)
        end
      end

      class << self
        # A module that extends Tools also gets [] and the secret helpers
        def extended(base)
          base.extend(Lookup)
          base.extend(Secrets)
        end

        # Global name => ToolDef registry shared by every scope that defines tools
        def registry
          @registry ||= {}
        end

        def registry_mutex
          @registry_mutex ||= Mutex.new
        end

        def register(tool_def)
          registry_mutex.synchronize { registry[tool_def.name] = tool_def }
          tool_def
        end

        # @return [ToolDef, nil]
        def lookup(name)
          registry_mutex.synchronize { registry[name.to_s] }
        end

        # Forget every registered tool (tests)
        def clear!
          registry_mutex.synchronize { registry.clear }
        end

        # Build a ToolDef from a bound Method
        # @param method [Method]
        # @param name [String, nil] tool name override
        def build(method, name: nil, **options)
          unknown = options.keys - TOOL_OPTIONS
          raise ConfigurationError, "unknown tool option(s): #{unknown.inspect}" unless unknown.empty?

          tool_name = (name || method.name).to_s
          input_schema = options.fetch(:input_schema) { SchemaBuilder.input_schema(method) }
          credentials = SecretScanner.scan(method)

          ToolDef.new(
            name: tool_name,
            description: options.fetch(:description) { humanize(method.name) },
            input_schema: input_schema,
            output_schema: options.fetch(:output_schema) { SchemaBuilder.default_output_schema },
            func: options[:external] ? nil : method,
            approval_required: options.fetch(:approval_required, false),
            timeout_seconds: options[:timeout_seconds],
            credentials: credentials + Array(options[:credentials]),
            stateful: options.fetch(:stateful, false),
            max_calls: options[:max_calls],
            retry_count: options.fetch(:retry_count, 2),
            retry_delay_seconds: options.fetch(:retry_delay_seconds, 2),
            retry_policy: options.fetch(:retry_policy, 'linear_backoff')
          )
        end

        # "get_weather" => "Get weather"
        def humanize(name)
          words = name.to_s.tr('_', ' ').strip
          return '' if words.empty?

          words[0].upcase + words[1..]
        end
      end

      # Mark a method as a tool
      # @param name [Symbol, String, Method] method name (what +def+ returns) or a Method
      # @param options [Hash] ToolDef overrides: description:, output_schema:, approval_required:,
      #   timeout_seconds:, credentials:, stateful:, max_calls:, retry_count:, retry_delay_seconds:, retry_policy:
      # @return [ToolDef]
      def tool(name, **options)
        method = name.is_a?(Method) ? name : resolve_tool_method(name.to_sym)
        tool_def = Tools.build(method, name: name.is_a?(Method) ? name.name : name, **options)
        tool_registry[tool_def.name] = tool_def
        Tools.register(tool_def)
      end

      # Override the description the LLM sees
      def describe(name, text)
        fetch_tool(name).description = text.to_s
      end

      # Require a human approval before the tool runs
      def requires_approval(name, enabled: true)
        fetch_tool(name).approval_required = enabled
      end

      # Declare secret names the scanner could not see (dynamic names)
      def tool_credentials(name, *secret_names)
        fetch_tool(name).add_credentials(*secret_names)
      end

      # Every tool defined in this scope, in definition order
      # @return [Array<ToolDef>]
      def tool_defs
        tool_registry.values
      end

      private

      def tool_registry
        @conductor_tool_registry ||= {} # rubocop:disable Naming/MemoizedInstanceVariableName
      end

      def fetch_tool(name)
        tool_registry[name.to_s] || Tools.lookup(name) ||
          raise(ConfigurationError, "no tool named #{name.inspect}; define it with `tool def #{name}(...)` first")
      end

      # Find the method behind +tool def name+ for the current receiver:
      # - top level / objects: the method is on self
      # - module with `extend Tools`: `def` made an instance method; module_function it
      # - class bodies (e.g. inside RSpec.describe): bind the instance method to a bare instance
      def resolve_tool_method(name)
        return method(name) if respond_to?(name, true)

        if is_a?(Module) && (method_defined?(name) || private_method_defined?(name))
          if instance_of?(Module)
            module_function(name)
            return method(name)
          end

          return instance_method(name).bind(allocate)
        end

        raise ConfigurationError, "tool #{name.inspect}: no such method on #{inspect}"
      end
    end
  end
end

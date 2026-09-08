# frozen_string_literal: true

require 'json'
require_relative '../errors'
require_relative 'secrets'
require_relative '../../http/models/task_result'

module Conductor
  module Agents
    # Executes one tool task: maps the task's inputData onto the tool method's keyword
    # arguments, runs it, and shapes the result for the server.
    #
    # The server sends the LLM's arguments as top-level keys plus a few injected keys
    # (method, _agent_state, _agent_tool_name, _allowed_commands) that are stripped here.
    # Missing required arguments, missing credentials and unserializable results are
    # terminal failures; anything raised by the tool itself is a retryable failure.
    module Dispatch
      INJECTED_KEYS = %w[method _agent_state _agent_tool_name _allowed_commands __conductor_agent_ctx__].freeze
      WORKER_ID = 'agent-sdk'
      TRUE_STRINGS = %w[true 1 yes].freeze
      FALSE_STRINGS = %w[false 0 no].freeze

      # Raised when the LLM omitted a required argument
      class MissingArgumentError < Error; end

      module_function

      # @param task [Http::Models::Task]
      # @param tool_def [ToolDef]
      # @return [Http::Models::TaskResult]
      def run_tool_task(task, tool_def, logger: nil)
        result = base_result(task)
        input = (task.input_data || {}).transform_keys(&:to_s)
        args = input.except(*INJECTED_KEYS)

        check_credentials!(tool_def)
        kwargs = coerce_args(args, tool_def)
        output = tool_def.func.call(**kwargs)
        return output if output.is_a?(Http::Models::TaskResult)

        result.status = Http::Models::TaskResultStatus::COMPLETED
        result.output_data = normalize_output(tool_def, output)
        result
      rescue MissingArgumentError, CredentialNotFoundError, ToolSerializationError => e
        logger&.error("tool #{tool_def.name}: #{e.message}")
        terminal_failure(result, e)
      rescue StandardError => e
        logger&.error("tool #{tool_def.name} raised #{e.class}: #{e.message}")
        result.status = Http::Models::TaskResultStatus::FAILED
        result.reason_for_incompletion = "#{e.class}: #{e.message}"
        result
      end

      # Map input keys to the tool's keyword arguments, coercing by the JSON schema
      # @return [Hash<Symbol, Object>]
      def coerce_args(args, tool_def)
        schema = tool_def.input_schema || {}
        properties = schema['properties'] || {}
        required = Array(schema['required'])
        accepts_rest = tool_def.func.respond_to?(:parameters) && tool_def.func.parameters.any? { |kind, _| kind == :keyrest }

        missing = required.reject { |name| args.key?(name) }
        raise MissingArgumentError, "tool #{tool_def.name}: missing required argument(s) #{missing.join(', ')}" unless missing.empty?

        args.each_with_object({}) do |(name, value), kwargs|
          if properties.key?(name)
            kwargs[name.to_sym] = coerce_value(value, properties[name])
          elsif accepts_rest || properties.empty?
            kwargs[name.to_sym] = value
          end
        end
      end

      # Coerce one value to its JSON schema type (LLMs often send numbers and JSON as strings)
      def coerce_value(value, property)
        return value unless property.is_a?(Hash)

        type = property['type']
        case type
        when 'integer'
          value.is_a?(String) ? (Integer(value, 10) rescue value) : value # rubocop:disable Style/RescueModifier
        when 'number'
          value.is_a?(String) ? (Float(value) rescue value) : value # rubocop:disable Style/RescueModifier
        when 'boolean'
          return value unless value.is_a?(String)

          lower = value.strip.downcase
          return true if TRUE_STRINGS.include?(lower)
          return false if FALSE_STRINGS.include?(lower)

          value
        when 'array', 'object'
          return value unless value.is_a?(String)

          parsed = JSON.parse(value)
          expected = type == 'array' ? Array : Hash
          parsed.is_a?(expected) ? parsed : value
        when 'string'
          value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value
        else
          value
        end
      rescue JSON::ParserError
        value
      end

      # Hash results go out as-is; anything else is wrapped as { "result" => value }
      def normalize_output(tool_def, output)
        data = output.is_a?(Hash) ? output.transform_keys(&:to_s) : { 'result' => output }
        begin
          JSON.generate(data)
        rescue StandardError => e
          raise ToolSerializationError, "tool #{tool_def.name} returned a non-JSON-serializable result: #{e.message}"
        end
        data
      end

      def check_credentials!(tool_def)
        tool_def.credentials.each { |name| Secrets.secret(name) }
      end

      def base_result(task)
        result = Http::Models::TaskResult.new
        result.task_id = task.task_id
        result.workflow_instance_id = task.workflow_instance_id
        result.worker_id = WORKER_ID
        result
      end

      def terminal_failure(result, error)
        result.status = Http::Models::TaskResultStatus::FAILED_WITH_TERMINAL_ERROR
        result.reason_for_incompletion = error.message
        result
      end
    end
  end
end

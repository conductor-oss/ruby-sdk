# frozen_string_literal: true

require_relative '../errors'
require_relative 'execution'

module Conductor
  module Agents
    # A tool call (or batch of them) waiting for a human decision.
    #
    #   agent.on_approval do |request|
    #     request.amount < 100 ? request.approve : request.reject('Needs a manager')
    #   end
    #
    # The server pauses on one HUMAN task per turn, so a request may carry several tool
    # calls; +tool_name+ and the argument accessors (request.amount) read the first one.
    class ApprovalRequest
      attr_reader :execution_id, :task_ref_name, :tool_calls, :response_schema, :raw

      # @param pending_tool [Hash] the SSE "waiting" event's pendingTool payload
      def initialize(execution_id, pending_tool, client:, execution: nil)
        @execution_id = execution_id
        @client = client
        @execution = execution
        @raw = pending_tool || {}
        @task_ref_name = @raw['taskRefName']
        @response_schema = @raw['response_schema']
        @tool_calls = extract_tool_calls(@raw)
        @responded = false
      end

      # First tool call's name
      def tool_name
        @tool_calls.first&.name
      end

      # First tool call's arguments (String keys)
      def arguments
        @tool_calls.first&.arguments || {}
      end

      def responded?
        @responded
      end

      # Let the tool run
      def approve
        complete_response { @client.approve(@execution_id) }
      end

      # Skip the tool; the run ends COMPLETED with finish_reason :rejected
      def reject(reason = '')
        complete_response { @client.reject(@execution_id, reason) }
      end

      # Free-text answer (human tools / feedback)
      def send_message(message)
        complete_response { @client.send_message(@execution_id, message) }
      end

      # Submit fields requested by response_schema (approval plus reviewer feedback,
      # or structured input for a human tool).
      def respond(body)
        complete_response { @client.respond(@execution_id, body) }
      end

      # request.amount, request.order_id ... read the first tool call's arguments
      def method_missing(name, *args, &block)
        key = name.to_s
        return arguments[key] if args.empty? && arguments.key?(key)

        super
      end

      def respond_to_missing?(name, include_private = false)
        arguments.key?(name.to_s) || super
      end

      def to_s
        calls = @tool_calls.map(&:to_s).join(', ')
        "#<Conductor::Agents::ApprovalRequest #{@execution_id} #{calls}>"
      end
      alias inspect to_s

      private

      def complete_response
        raise Error, 'approval request already answered' if @responded

        yield
        @responded = true
        @execution&.clear_waiting
        self
      end

      def extract_tool_calls(raw)
        calls = raw['toolCalls'] || raw['tool_calls']
        if calls.is_a?(Array) && !calls.empty?
          return calls.map do |c|
            c = c.transform_keys(&:to_s)
            ToolCall.new(name: c['name'], arguments: (c['args'] || c['arguments'] || c['parameters'] || {}).transform_keys(&:to_s))
          end
        end

        name = raw['tool_name'] || raw['toolName']
        return [] if name.nil?

        [ToolCall.new(name: name, arguments: (raw['parameters'] || raw['args'] || {}).transform_keys(&:to_s))]
      end
    end
  end
end

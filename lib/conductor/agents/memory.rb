# frozen_string_literal: true

module Conductor
  module Agents
    # Conversation history seeded into the agent (memory: on Agent). Messages are
    # prepended to the LLM conversation by the server; max_messages trims the oldest
    # non-system messages first.
    class ConversationMemory
      attr_reader :messages, :max_messages

      def initialize(messages: [], max_messages: nil)
        @messages = messages.map { |m| m.transform_keys(&:to_s) }
        @max_messages = max_messages
        trim
      end

      def add_user_message(content)
        push('role' => 'user', 'message' => content.to_s)
      end

      def add_assistant_message(content)
        push('role' => 'assistant', 'message' => content.to_s)
      end

      def add_system_message(content)
        push('role' => 'system', 'message' => content.to_s)
      end

      def add_tool_call(tool_name, arguments, task_reference_name: nil)
        ref = task_reference_name || "#{tool_name}_ref"
        push('role' => 'tool_call', 'message' => '',
             'tool_calls' => [{ 'name' => tool_name.to_s, 'taskReferenceName' => ref, 'input' => arguments }])
      end

      def add_tool_result(tool_name, result, task_reference_name: nil)
        ref = task_reference_name || "#{tool_name}_ref"
        push('role' => 'tool', 'message' => result.to_s, 'toolCallId' => ref, 'taskReferenceName' => ref)
      end

      # Deep copy of the messages
      def to_chat_messages
        Marshal.load(Marshal.dump(@messages))
      end

      def clear
        @messages.clear
      end

      def empty?
        @messages.empty?
      end

      private

      def push(message)
        @messages << message
        trim
      end

      def trim
        return unless @max_messages && @messages.size > @max_messages

        system_msgs, others = @messages.partition { |m| m['role'] == 'system' }
        if system_msgs.size >= @max_messages
          @messages = system_msgs.last(@max_messages)
          return
        end

        keep = @max_messages - system_msgs.size
        dropped = others.first(others.size - keep)
        @messages = @messages.reject { |m| dropped.any? { |d| d.equal?(m) } }
      end
    end
  end
end

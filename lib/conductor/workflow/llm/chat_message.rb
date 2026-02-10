# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # Role constants for ChatMessage
      module Role
        USER = 'user'
        ASSISTANT = 'assistant'
        SYSTEM = 'system'
        TOOL_CALL = 'tool_call'
        TOOL = 'tool'
      end

      # ChatMessage represents a single message in an LLM chat conversation
      class ChatMessage
        attr_accessor :role, :message, :media, :mime_type, :tool_calls

        # @param role [String] The role (use Role constants)
        # @param message [String] The message content
        # @param media [Array<String>, nil] Optional media URLs
        # @param mime_type [String, nil] Optional MIME type for media
        # @param tool_calls [Array<ToolCall>, nil] Optional tool calls
        def initialize(role:, message:, media: nil, mime_type: nil, tool_calls: nil)
          @role = role
          @message = message
          @media = media
          @mime_type = mime_type
          @tool_calls = tool_calls
        end

        # Convert to hash for serialization
        # @return [Hash] The message as a hash with camelCase keys
        def to_h
          result = {
            'role' => @role,
            'message' => @message
          }
          result['media'] = @media if @media && !@media.empty?
          result['mimeType'] = @mime_type if @mime_type
          result['toolCalls'] = @tool_calls.map(&:to_h) if @tool_calls && !@tool_calls.empty?
          result
        end
      end
    end
  end
end

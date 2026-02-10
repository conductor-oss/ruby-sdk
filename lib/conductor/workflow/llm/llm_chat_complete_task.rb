# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmChatCompleteTask - Chat completion using an LLM provider
      class LlmChatCompleteTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param llm_provider [String] LLM provider integration name
        # @param model [String] Model name (e.g. 'gpt-4')
        # @param messages [Array<ChatMessage>, nil] Chat messages
        # @param instructions_template [String, nil] Prompt template name for instructions
        # @param template_variables [Hash, nil] Variables for the prompt template
        # @param prompt_version [Integer, nil] Prompt template version
        # @param tools [Array<ToolSpec>, nil] Tool specifications for function calling
        # @param user_input [String, nil] User input text
        # @param json_output [Boolean] Whether to request JSON output
        # @param google_search_retrieval [Boolean] Enable Google search retrieval
        # @param input_schema [Hash, nil] JSON schema for input
        # @param output_schema [Hash, nil] JSON schema for output
        # @param output_mime_type [String, nil] Output MIME type
        # @param thinking_token_limit [Integer, nil] Token limit for thinking
        # @param reasoning_effort [String, nil] Reasoning effort level
        # @param output_location [String, nil] Output location
        # @param voice [String, nil] Voice for audio output
        # @param participants [Hash, nil] Conversation participants
        # @param stop_words [Array<String>, nil] Stop words
        # @param max_tokens [Integer, nil] Max tokens in response
        # @param temperature [Float, nil] Sampling temperature
        # @param top_p [Float, nil] Top-p sampling
        # @param top_k [Integer, nil] Top-k sampling
        # @param frequency_penalty [Float, nil] Frequency penalty
        # @param presence_penalty [Float, nil] Presence penalty
        # @param max_results [Integer, nil] Max results
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, llm_provider, model,
                       messages: nil, instructions_template: nil, template_variables: nil,
                       prompt_version: nil, tools: nil, user_input: nil,
                       json_output: false, google_search_retrieval: false,
                       input_schema: nil, output_schema: nil, output_mime_type: nil,
                       thinking_token_limit: nil, reasoning_effort: nil,
                       output_location: nil, voice: nil, participants: nil,
                       stop_words: nil, max_tokens: nil, temperature: nil,
                       top_p: nil, top_k: nil, frequency_penalty: nil,
                       presence_penalty: nil, max_results: nil, task_name: nil)
          input_params = {
            'llmProvider' => llm_provider,
            'model' => model
          }

          input_params['promptVariables'] = template_variables if template_variables
          input_params['promptVersion'] = prompt_version unless prompt_version.nil?
          input_params['messages'] = messages.map(&:to_h) if messages
          input_params['instructions'] = instructions_template if instructions_template
          input_params['userInput'] = user_input if user_input
          input_params['tools'] = tools.map(&:to_h) if tools && !tools.empty?
          input_params['jsonOutput'] = json_output if json_output
          input_params['googleSearchRetrieval'] = google_search_retrieval if google_search_retrieval
          input_params['inputSchema'] = input_schema if input_schema
          input_params['outputSchema'] = output_schema if output_schema
          input_params['outputMimeType'] = output_mime_type if output_mime_type
          input_params['thinkingTokenLimit'] = thinking_token_limit unless thinking_token_limit.nil?
          input_params['reasoningEffort'] = reasoning_effort if reasoning_effort
          input_params['outputLocation'] = output_location if output_location
          input_params['voice'] = voice if voice
          input_params['participants'] = participants if participants
          input_params['stopWords'] = stop_words if stop_words && !stop_words.empty?
          input_params['maxTokens'] = max_tokens unless max_tokens.nil?
          input_params['temperature'] = temperature unless temperature.nil?
          input_params['topP'] = top_p unless top_p.nil?
          input_params['topK'] = top_k unless top_k.nil?
          input_params['frequencyPenalty'] = frequency_penalty unless frequency_penalty.nil?
          input_params['presencePenalty'] = presence_penalty unless presence_penalty.nil?
          input_params['maxResults'] = max_results unless max_results.nil?

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_CHAT_COMPLETE,
            task_name: task_name || 'llm_chat_complete',
            input_parameters: input_params
          )
        end

        # Add or merge prompt variables (fluent interface)
        # @param variables [Hash] Variables to merge
        # @return [self]
        def prompt_variables(variables)
          @input_parameters['promptVariables'] ||= {}
          @input_parameters['promptVariables'].merge!(variables)
          self
        end

        # Set a single prompt variable (fluent interface)
        # @param variable [String] Variable name
        # @param value [Object] Variable value
        # @return [self]
        def prompt_variable(variable, value)
          @input_parameters['promptVariables'] ||= {}
          @input_parameters['promptVariables'][variable] = value
          self
        end
      end
    end
  end
end

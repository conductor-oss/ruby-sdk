# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmTextCompleteTask - Text completion using an LLM provider with a named prompt
      class LlmTextCompleteTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param llm_provider [String] LLM provider integration name
        # @param model [String] Model name
        # @param prompt_name [String] Name of the registered prompt template
        # @param prompt_version [Integer, nil] Prompt template version
        # @param stop_words [Array<String>, nil] Stop words
        # @param max_tokens [Integer, nil] Max tokens in response
        # @param temperature [Float, nil] Sampling temperature
        # @param top_p [Float, nil] Top-p sampling
        # @param top_k [Integer, nil] Top-k sampling
        # @param frequency_penalty [Float, nil] Frequency penalty
        # @param presence_penalty [Float, nil] Presence penalty
        # @param max_results [Integer, nil] Max results
        # @param json_output [Boolean] Whether to request JSON output
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, llm_provider, model, prompt_name,
                       prompt_version: nil, stop_words: nil, max_tokens: nil,
                       temperature: nil, top_p: nil, top_k: nil,
                       frequency_penalty: nil, presence_penalty: nil,
                       max_results: nil, json_output: false, task_name: nil)
          input_params = {
            'llmProvider' => llm_provider,
            'model' => model,
            'promptName' => prompt_name
          }

          input_params['promptVersion'] = prompt_version unless prompt_version.nil?
          input_params['stopWords'] = stop_words if stop_words && !stop_words.empty?
          input_params['maxTokens'] = max_tokens unless max_tokens.nil?
          input_params['temperature'] = temperature unless temperature.nil?
          input_params['topP'] = top_p unless top_p.nil?
          input_params['topK'] = top_k unless top_k.nil?
          input_params['frequencyPenalty'] = frequency_penalty unless frequency_penalty.nil?
          input_params['presencePenalty'] = presence_penalty unless presence_penalty.nil?
          input_params['maxResults'] = max_results unless max_results.nil?
          input_params['jsonOutput'] = json_output if json_output

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_TEXT_COMPLETE,
            task_name: task_name || 'llm_text_complete',
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

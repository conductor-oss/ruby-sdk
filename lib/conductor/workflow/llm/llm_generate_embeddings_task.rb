# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmGenerateEmbeddingsTask - Generate vector embeddings using an LLM provider
      class LlmGenerateEmbeddingsTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param llm_provider [String] LLM provider integration name
        # @param model [String] Embedding model name
        # @param text [String] Text to generate embeddings for
        # @param dimensions [Integer, nil] Embedding dimensions
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, llm_provider, model, text,
                       dimensions: nil, task_name: nil)
          input_params = {
            'llmProvider' => llm_provider,
            'model' => model,
            'text' => text
          }
          input_params['dimensions'] = dimensions unless dimensions.nil?

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_GENERATE_EMBEDDINGS,
            task_name: task_name || 'llm_generate_embeddings',
            input_parameters: input_params
          )
        end
      end
    end
  end
end

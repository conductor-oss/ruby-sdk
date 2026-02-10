# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmSearchEmbeddingsTask - Search a vector database by embeddings
      class LlmSearchEmbeddingsTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param vector_db [String] Vector DB integration name
        # @param index [String] Index/collection name
        # @param embeddings [Array<Float>] Embedding vector to search for
        # @param namespace [String, nil] Namespace/partition
        # @param max_results [Integer] Max results (default: 1)
        # @param dimensions [Integer, nil] Embedding dimensions
        # @param embedding_model [String, nil] Embedding model name
        # @param embedding_model_provider [String, nil] Embedding provider name
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, vector_db, index, embeddings,
                       namespace: nil, max_results: 1, dimensions: nil,
                       embedding_model: nil, embedding_model_provider: nil,
                       task_name: nil)
          input_params = {
            'vectorDB' => vector_db,
            'index' => index,
            'embeddings' => embeddings,
            'maxResults' => max_results
          }
          input_params['namespace'] = namespace if namespace
          input_params['dimensions'] = dimensions unless dimensions.nil?
          input_params['embeddingModel'] = embedding_model if embedding_model
          input_params['embeddingModelProvider'] = embedding_model_provider if embedding_model_provider

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_SEARCH_EMBEDDINGS,
            task_name: task_name || 'llm_search_embeddings',
            input_parameters: input_params
          )
        end
      end
    end
  end
end

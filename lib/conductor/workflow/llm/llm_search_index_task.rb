# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmSearchIndexTask - Search a vector database index
      class LlmSearchIndexTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param vector_db [String] Vector DB integration name
        # @param namespace [String] Namespace/partition
        # @param index [String] Index/collection name
        # @param embedding_model_provider [String] Embedding provider name
        # @param embedding_model [String] Embedding model name
        # @param query [String] Search query
        # @param max_results [Integer] Max results to return (default: 1)
        # @param dimensions [Integer, nil] Embedding dimensions
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, vector_db, namespace, index,
                       embedding_model_provider, embedding_model, query,
                       max_results: 1, dimensions: nil, task_name: nil)
          input_params = {
            'vectorDB' => vector_db,
            'namespace' => namespace,
            'index' => index,
            'embeddingModelProvider' => embedding_model_provider,
            'embeddingModel' => embedding_model,
            'query' => query,
            'maxResults' => max_results
          }
          input_params['dimensions'] = dimensions unless dimensions.nil?

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_SEARCH_INDEX,
            task_name: task_name || 'llm_search_index',
            input_parameters: input_params
          )
        end
      end
    end
  end
end

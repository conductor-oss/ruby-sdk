# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmStoreEmbeddingsTask - Store embedding vectors in a vector database
      class LlmStoreEmbeddingsTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param vector_db [String] Vector DB integration name
        # @param index [String] Index/collection name
        # @param embeddings [Array<Float>] Embedding vector to store
        # @param namespace [String, nil] Namespace/partition
        # @param id [String, nil] Document ID
        # @param metadata [Hash, nil] Document metadata
        # @param embedding_model [String, nil] Model name used to generate embeddings
        # @param embedding_model_provider [String, nil] Provider used to generate embeddings
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, vector_db, index, embeddings,
                       namespace: nil, id: nil, metadata: nil,
                       embedding_model: nil, embedding_model_provider: nil,
                       task_name: nil)
          input_params = {
            'vectorDB' => vector_db,
            'index' => index,
            'embeddings' => embeddings
          }
          input_params['namespace'] = namespace if namespace
          input_params['id'] = id if id
          input_params['metadata'] = metadata if metadata
          input_params['embeddingModel'] = embedding_model if embedding_model
          input_params['embeddingModelProvider'] = embedding_model_provider if embedding_model_provider

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_STORE_EMBEDDINGS,
            task_name: task_name || 'llm_store_embeddings',
            input_parameters: input_params
          )
        end
      end
    end
  end
end

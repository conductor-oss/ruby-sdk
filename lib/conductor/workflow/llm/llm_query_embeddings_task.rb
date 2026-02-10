# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmQueryEmbeddingsTask - Query a vector database by embeddings
      class LlmQueryEmbeddingsTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param vector_db [String] Vector DB integration name
        # @param index [String] Index/collection name
        # @param embeddings [Array<Float>] Embedding vector to search for
        # @param namespace [String, nil] Namespace/partition
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, vector_db, index, embeddings,
                       namespace: nil, task_name: nil)
          input_params = {
            'vectorDB' => vector_db,
            'index' => index,
            'embeddings' => embeddings
          }
          input_params['namespace'] = namespace if namespace

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_GET_EMBEDDINGS,
            task_name: task_name || 'llm_get_embeddings',
            input_parameters: input_params
          )
        end
      end
    end
  end
end

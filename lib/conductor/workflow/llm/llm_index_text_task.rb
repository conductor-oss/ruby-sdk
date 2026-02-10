# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmIndexTextTask - Index text into a vector database
      class LlmIndexTextTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param vector_db [String] Vector DB integration name
        # @param index [String] Index/collection name
        # @param embedding_model [EmbeddingModel] Embedding model to use
        # @param text [String] Text to index
        # @param doc_id [String] Document identifier
        # @param namespace [String, nil] Namespace/partition
        # @param metadata [Hash, nil] Document metadata
        # @param url [String, nil] URL of the document
        # @param chunk_size [Integer, nil] Chunk size for splitting
        # @param chunk_overlap [Integer, nil] Overlap between chunks
        # @param dimensions [Integer, nil] Embedding dimensions
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, vector_db, index, embedding_model, text, doc_id,
                       namespace: nil, metadata: nil, url: nil,
                       chunk_size: nil, chunk_overlap: nil, dimensions: nil,
                       task_name: nil)
          input_params = {
            'vectorDB' => vector_db,
            'index' => index,
            'embeddingModelProvider' => embedding_model.provider,
            'embeddingModel' => embedding_model.model,
            'text' => text,
            'docId' => doc_id
          }
          input_params['metadata'] = metadata if metadata
          input_params['namespace'] = namespace if namespace
          input_params['url'] = url if url
          input_params['chunkSize'] = chunk_size unless chunk_size.nil?
          input_params['chunkOverlap'] = chunk_overlap unless chunk_overlap.nil?
          input_params['dimensions'] = dimensions unless dimensions.nil?

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_INDEX_TEXT,
            task_name: task_name || 'llm_index_text',
            input_parameters: input_params
          )
        end
      end
    end
  end
end

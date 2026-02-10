# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # LlmIndexDocumentTask - Index a document from a URL into a vector database
      # Uses the same task type as LlmIndexTextTask (LLM_INDEX_TEXT)
      class LlmIndexDocumentTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param vector_db [String] Vector DB integration name
        # @param namespace [String] Namespace/partition
        # @param embedding_model [EmbeddingModel] Embedding model to use
        # @param index [String] Index/collection name
        # @param url [String] URL of the document to index
        # @param media_type [String] MIME type of the document
        # @param chunk_size [Integer, nil] Chunk size for splitting
        # @param chunk_overlap [Integer, nil] Overlap between chunks
        # @param doc_id [String, nil] Optional document identifier
        # @param metadata [Hash, nil] Document metadata
        # @param dimensions [Integer, nil] Embedding dimensions
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, vector_db, namespace, embedding_model, index, url, media_type,
                       chunk_size: nil, chunk_overlap: nil, doc_id: nil,
                       metadata: nil, dimensions: nil, task_name: nil)
          input_params = {
            'vectorDB' => vector_db,
            'namespace' => namespace,
            'index' => index,
            'embeddingModelProvider' => embedding_model.provider,
            'embeddingModel' => embedding_model.model,
            'url' => url,
            'mediaType' => media_type
          }
          input_params['metadata'] = metadata if metadata
          input_params['chunkSize'] = chunk_size unless chunk_size.nil?
          input_params['chunkOverlap'] = chunk_overlap unless chunk_overlap.nil?
          input_params['docId'] = doc_id if doc_id
          input_params['dimensions'] = dimensions unless dimensions.nil?

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::LLM_INDEX_TEXT, # Same task type as LlmIndexTextTask
            task_name: task_name || 'llm_index_text',
            input_parameters: input_params
          )
        end
      end
    end
  end
end

# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # GetDocumentTask - Retrieve and parse a document from a URL
      class GetDocumentTask < TaskInterface
        # @param task_name [String] Task definition name
        # @param task_ref_name [String] Unique reference name
        # @param url [String] URL of the document
        # @param media_type [String] MIME type of the document
        def initialize(task_name, task_ref_name, url, media_type)
          input_params = {
            'url' => url,
            'mediaType' => media_type
          }

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::GET_DOCUMENT,
            task_name: task_name,
            input_parameters: input_params
          )
        end
      end
    end
  end
end

# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # EmbeddingModel encapsulates the provider and model name for embeddings
      class EmbeddingModel
        attr_reader :provider, :model

        # @param provider [String] The embedding provider name (e.g. 'openai')
        # @param model [String] The model name (e.g. 'text-embedding-ada-002')
        def initialize(provider:, model:)
          @provider = provider
          @model = model
        end
      end
    end
  end
end

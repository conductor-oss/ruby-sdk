# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # PromptTemplateTestRequest model - request to test a prompt template
      class PromptTemplateTestRequest < BaseModel
        SWAGGER_TYPES = {
          llm_provider: 'String',
          model: 'String',
          prompt: 'String',
          prompt_variables: 'Hash<String, Object>',
          stop_words: 'Array<String>',
          temperature: 'Float',
          top_p: 'Float'
        }.freeze

        ATTRIBUTE_MAP = {
          llm_provider: :llmProvider,
          model: :model,
          prompt: :prompt,
          prompt_variables: :promptVariables,
          stop_words: :stopWords,
          temperature: :temperature,
          top_p: :topP
        }.freeze

        attr_accessor :llm_provider, :model, :prompt, :prompt_variables,
                      :stop_words, :temperature, :top_p

        def initialize(params = {})
          @llm_provider = params[:llm_provider]
          @model = params[:model]
          @prompt = params[:prompt]
          @prompt_variables = params[:prompt_variables]
          @stop_words = params[:stop_words]
          @temperature = params[:temperature]
          @top_p = params[:top_p]
        end
      end
    end
  end
end

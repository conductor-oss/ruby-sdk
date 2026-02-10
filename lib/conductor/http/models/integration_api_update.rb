# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Frequency constants for integration API updates
      module Frequency
        DAILY = 'daily'
        WEEKLY = 'weekly'
        MONTHLY = 'monthly'
      end

      # IntegrationApiUpdate model - request to create/update an integration API
      class IntegrationApiUpdate < BaseModel
        SWAGGER_TYPES = {
          configuration: 'Hash<String, Object>',
          description: 'String',
          enabled: 'Boolean',
          max_tokens: 'Integer',
          frequency: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          configuration: :configuration,
          description: :description,
          enabled: :enabled,
          max_tokens: :maxTokens,
          frequency: :frequency
        }.freeze

        attr_accessor :configuration, :description, :enabled, :max_tokens, :frequency

        def initialize(params = {})
          @configuration = params[:configuration]
          @description = params[:description]
          @enabled = params[:enabled]
          @max_tokens = params[:max_tokens]
          @frequency = params[:frequency]
        end
      end
    end
  end
end

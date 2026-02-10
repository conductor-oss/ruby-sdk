# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # IntegrationUpdate model - request to create/update an integration provider
      class IntegrationUpdate < BaseModel
        SWAGGER_TYPES = {
          category: 'String',
          configuration: 'Hash<String, Object>',
          description: 'String',
          enabled: 'Boolean',
          type: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          category: :category,
          configuration: :configuration,
          description: :description,
          enabled: :enabled,
          type: :type
        }.freeze

        attr_accessor :category, :configuration, :description, :enabled, :type

        def initialize(params = {})
          @category = params[:category]
          @configuration = params[:configuration]
          @description = params[:description]
          @enabled = params[:enabled]
          @type = params[:type]
        end
      end
    end
  end
end

# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Integration category constants
      module IntegrationCategory
        API = 'API'
        AI_MODEL = 'AI_MODEL'
        VECTOR_DB = 'VECTOR_DB'
        RELATIONAL_DB = 'RELATIONAL_DB'
      end

      # Integration model - represents an integration provider
      class Integration < BaseModel
        SWAGGER_TYPES = {
          category: 'String',
          configuration: 'Hash<String, Object>',
          created_by: 'String',
          created_on: 'Integer',
          description: 'String',
          enabled: 'Boolean',
          models_count: 'Integer',
          name: 'String',
          tags: 'Array<TagObject>',
          type: 'String',
          updated_by: 'String',
          updated_on: 'Integer',
          apis: 'Array<IntegrationApi>'
        }.freeze

        ATTRIBUTE_MAP = {
          category: :category,
          configuration: :configuration,
          created_by: :createdBy,
          created_on: :createdOn,
          description: :description,
          enabled: :enabled,
          models_count: :modelsCount,
          name: :name,
          tags: :tags,
          type: :type,
          updated_by: :updatedBy,
          updated_on: :updatedOn,
          apis: :apis
        }.freeze

        attr_accessor :category, :configuration, :created_by, :created_on,
                      :description, :enabled, :models_count, :name, :tags,
                      :type, :updated_by, :updated_on, :apis

        def initialize(params = {})
          @category = params[:category]
          @configuration = params[:configuration]
          @created_by = params[:created_by]
          @created_on = params[:created_on]
          @description = params[:description]
          @enabled = params[:enabled]
          @models_count = params[:models_count]
          @name = params[:name]
          @tags = params[:tags]
          @type = params[:type]
          @updated_by = params[:updated_by]
          @updated_on = params[:updated_on]
          @apis = params[:apis]
        end
      end
    end
  end
end

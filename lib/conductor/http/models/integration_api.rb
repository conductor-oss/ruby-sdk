# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # IntegrationApi model - represents an API/model within an integration provider
      class IntegrationApi < BaseModel
        SWAGGER_TYPES = {
          api: 'String',
          configuration: 'Hash<String, Object>',
          created_by: 'String',
          created_on: 'Integer',
          description: 'String',
          enabled: 'Boolean',
          integration_name: 'String',
          tags: 'Array<TagObject>',
          updated_by: 'String',
          updated_on: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          api: :api,
          configuration: :configuration,
          created_by: :createdBy,
          created_on: :createdOn,
          description: :description,
          enabled: :enabled,
          integration_name: :integrationName,
          tags: :tags,
          updated_by: :updatedBy,
          updated_on: :updatedOn
        }.freeze

        attr_accessor :api, :configuration, :created_by, :created_on,
                      :description, :enabled, :integration_name, :tags,
                      :updated_by, :updated_on

        def initialize(params = {})
          @api = params[:api]
          @configuration = params[:configuration]
          @created_by = params[:created_by]
          @created_on = params[:created_on]
          @description = params[:description]
          @enabled = params[:enabled]
          @integration_name = params[:integration_name]
          @tags = params[:tags]
          @updated_by = params[:updated_by]
          @updated_on = params[:updated_on]
        end
      end
    end
  end
end

# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # PromptTemplate model - AI prompt template
      class PromptTemplate < BaseModel
        SWAGGER_TYPES = {
          created_by: 'String',
          create_time: 'Integer',
          description: 'String',
          integrations: 'Array<String>',
          name: 'String',
          owner_app: 'String',
          tags: 'Array<TagObject>',
          template: 'String',
          updated_by: 'String',
          update_time: 'Integer',
          variables: 'Array<String>',
          version: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          created_by: :createdBy,
          create_time: :createTime,
          description: :description,
          integrations: :integrations,
          name: :name,
          owner_app: :ownerApp,
          tags: :tags,
          template: :template,
          updated_by: :updatedBy,
          update_time: :updateTime,
          variables: :variables,
          version: :version
        }.freeze

        attr_accessor :created_by, :create_time, :description, :integrations,
                      :name, :owner_app, :tags, :template, :updated_by,
                      :update_time, :variables, :version

        def initialize(params = {})
          @created_by = params[:created_by]
          @create_time = params[:create_time]
          @description = params[:description]
          @integrations = params[:integrations]
          @name = params[:name]
          @owner_app = params[:owner_app]
          @tags = params[:tags]
          @template = params[:template]
          @updated_by = params[:updated_by]
          @update_time = params[:update_time]
          @variables = params[:variables]
          @version = params[:version] || 1
        end
      end
    end
  end
end

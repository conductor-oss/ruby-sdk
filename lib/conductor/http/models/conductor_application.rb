# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # ConductorApplication model - represents an application in Conductor
      class ConductorApplication < BaseModel
        SWAGGER_TYPES = {
          id: 'String',
          name: 'String',
          created_by: 'String',
          create_time: 'Integer',
          update_time: 'Integer',
          updated_by: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          id: :id,
          name: :name,
          created_by: :createdBy,
          create_time: :createTime,
          update_time: :updateTime,
          updated_by: :updatedBy
        }.freeze

        attr_accessor :id, :name, :created_by, :create_time, :update_time, :updated_by

        def initialize(params = {})
          @id = params[:id]
          @name = params[:name]
          @created_by = params[:created_by]
          @create_time = params[:create_time]
          @update_time = params[:update_time]
          @updated_by = params[:updated_by]
        end
      end
    end
  end
end

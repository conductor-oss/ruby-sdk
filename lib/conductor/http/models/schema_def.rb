# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Schema type constants
      module SchemaType
        JSON = 'JSON'
        AVRO = 'AVRO'
        PROTOBUF = 'PROTOBUF'
      end

      # SchemaDef model - JSON/Avro/Protobuf schema definition
      class SchemaDef < BaseModel
        SWAGGER_TYPES = {
          owner_app: 'String',
          create_time: 'Integer',
          update_time: 'Integer',
          created_by: 'String',
          updated_by: 'String',
          name: 'String',
          version: 'Integer',
          type: 'String',
          data: 'Hash<String, Object>',
          external_ref: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          owner_app: :ownerApp,
          create_time: :createTime,
          update_time: :updateTime,
          created_by: :createdBy,
          updated_by: :updatedBy,
          name: :name,
          version: :version,
          type: :type,
          data: :data,
          external_ref: :externalRef
        }.freeze

        attr_accessor :owner_app, :create_time, :update_time, :created_by,
                      :updated_by, :name, :version, :type, :data, :external_ref

        def initialize(params = {})
          @owner_app = params[:owner_app]
          @create_time = params[:create_time]
          @update_time = params[:update_time]
          @created_by = params[:created_by]
          @updated_by = params[:updated_by]
          @name = params[:name]
          @version = params[:version] || 1
          @type = params[:type]
          @data = params[:data]
          @external_ref = params[:external_ref]
        end
      end
    end
  end
end

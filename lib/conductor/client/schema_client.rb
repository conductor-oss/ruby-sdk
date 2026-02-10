# frozen_string_literal: true

module Conductor
  module Client
    # SchemaClient - High-level client for schema management operations (Orkes)
    class SchemaClient
      def initialize(api_client)
        @schema_api = Http::Api::SchemaResourceApi.new(api_client)
      end

      def register_schema(schema, new_version: false)
        @schema_api.save(schema, new_version: new_version)
      end

      def get_schema(schema_name, version)
        @schema_api.get_schema_by_name_and_version(schema_name, version)
      end

      def get_all_schemas
        @schema_api.get_all_schemas
      end

      def delete_schema(schema_name, version)
        @schema_api.delete_schema_by_name_and_version(schema_name, version)
      end

      def delete_schema_by_name(schema_name)
        @schema_api.delete_schema_by_name(schema_name)
      end
    end
  end
end

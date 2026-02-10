# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # SchemaResourceApi - API for schema management operations (Orkes)
      class SchemaResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Save a schema definition
        # @param [SchemaDef] body Schema definition
        # @param [Boolean] new_version Whether to create a new version
        # @return [void]
        def save(body, new_version: false)
          @api_client.call_api(
            '/schema',
            'POST',
            query_params: { newVersion: new_version },
            body: body,
            return_http_data_only: true
          )
        end

        # Get a schema by name and version
        # @param [String] name Schema name
        # @param [Integer] version Schema version
        # @return [SchemaDef]
        def get_schema_by_name_and_version(name, version)
          @api_client.call_api(
            '/schema/{name}/{version}',
            'GET',
            path_params: { name: name, version: version },
            return_type: 'SchemaDef',
            return_http_data_only: true
          )
        end

        # Get all schemas
        # @return [Array<SchemaDef>]
        def get_all_schemas
          @api_client.call_api(
            '/schema',
            'GET',
            return_type: 'Array<SchemaDef>',
            return_http_data_only: true
          )
        end

        # Delete a schema by name and version
        # @param [String] name Schema name
        # @param [Integer] version Schema version
        # @return [void]
        def delete_schema_by_name_and_version(name, version)
          @api_client.call_api(
            '/schema/{name}/{version}',
            'DELETE',
            path_params: { name: name, version: version },
            return_http_data_only: true
          )
        end

        # Delete all versions of a schema by name
        # @param [String] name Schema name
        # @return [void]
        def delete_schema_by_name(name)
          @api_client.call_api(
            '/schema/{name}',
            'DELETE',
            path_params: { name: name },
            return_http_data_only: true
          )
        end
      end
    end
  end
end

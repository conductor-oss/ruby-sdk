# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # SecretResourceApi - API for secret management operations (Orkes)
      class SecretResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Store a secret value
        # @param [String] key Secret key
        # @param [String] value Secret value
        # @return [void]
        def put_secret(value, key)
          @api_client.call_api(
            '/secrets/{key}',
            'PUT',
            path_params: { key: key },
            body: value,
            return_http_data_only: true
          )
        end

        # Get a secret value
        # @param [String] key Secret key
        # @return [String]
        def get_secret(key)
          @api_client.call_api(
            '/secrets/{key}',
            'GET',
            path_params: { key: key },
            return_type: 'String',
            return_http_data_only: true
          )
        end

        # List all secret names
        # @return [Array<String>]
        def list_all_secret_names
          @api_client.call_api(
            '/secrets',
            'POST',
            return_type: 'Array<String>',
            return_http_data_only: true
          )
        end

        # List secrets that user can grant access to
        # @return [Array<String>]
        def list_secrets_that_user_can_grant_access_to
          @api_client.call_api(
            '/secrets',
            'GET',
            return_type: 'Array<String>',
            return_http_data_only: true
          )
        end

        # Delete a secret
        # @param [String] key Secret key
        # @return [void]
        def delete_secret(key)
          @api_client.call_api(
            '/secrets/{key}',
            'DELETE',
            path_params: { key: key },
            return_http_data_only: true
          )
        end

        # Check if a secret exists
        # @param [String] key Secret key
        # @return [Boolean]
        def secret_exists(key)
          @api_client.call_api(
            '/secrets/{key}/exists',
            'GET',
            path_params: { key: key },
            return_type: 'Boolean',
            return_http_data_only: true
          )
        end

        # Set tags for a secret
        # @param [Array<TagObject>] tags Tags to set
        # @param [String] key Secret key
        # @return [void]
        def put_tag_for_secret(tags, key)
          @api_client.call_api(
            '/secrets/{key}/tags',
            'PUT',
            path_params: { key: key },
            body: tags,
            return_http_data_only: true
          )
        end

        # Get tags for a secret
        # @param [String] key Secret key
        # @return [Array<TagObject>]
        def get_tags(key)
          @api_client.call_api(
            '/secrets/{key}/tags',
            'GET',
            path_params: { key: key },
            return_type: 'Array<TagObject>',
            return_http_data_only: true
          )
        end

        # Delete tags for a secret
        # @param [Array<TagObject>] tags Tags to delete
        # @param [String] key Secret key
        # @return [Array<TagObject>]
        def delete_tag_for_secret(tags, key)
          @api_client.call_api(
            '/secrets/{key}/tags',
            'DELETE',
            path_params: { key: key },
            body: tags,
            return_type: 'Array<TagObject>',
            return_http_data_only: true
          )
        end
      end
    end
  end
end

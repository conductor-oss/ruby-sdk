# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # UserResourceApi - API for user management operations (Orkes)
      class UserResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Create or update a user
        def upsert_user(body, id)
          @api_client.call_api('/users/{id}', 'PUT', path_params: { id: id }, body: body, return_type: 'ConductorUser',
                                                     return_http_data_only: true)
        end

        # Get a user by ID
        def get_user(id)
          @api_client.call_api('/users/{id}', 'GET', path_params: { id: id }, return_type: 'ConductorUser',
                                                     return_http_data_only: true)
        end

        # List all users
        def list_users(apps: false)
          @api_client.call_api('/users', 'GET', query_params: { apps: apps }, return_type: 'Array<ConductorUser>',
                                                return_http_data_only: true)
        end

        # Delete a user
        def delete_user(id)
          @api_client.call_api('/users/{id}', 'DELETE', path_params: { id: id }, return_http_data_only: true)
        end

        # Check permissions for a user
        def check_permissions(user_id, target_type, target_id)
          @api_client.call_api(
            '/users/{userId}/checkPermissions',
            'GET',
            path_params: { userId: user_id },
            query_params: { type: target_type, id: target_id },
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Get granted permissions for a user
        def get_granted_permissions(user_id)
          @api_client.call_api('/users/{userId}/permissions', 'GET', path_params: { userId: user_id },
                                                                     return_type: 'Object', return_http_data_only: true)
        end
      end
    end
  end
end

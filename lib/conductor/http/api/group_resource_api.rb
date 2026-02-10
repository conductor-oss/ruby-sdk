# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # GroupResourceApi - API for group management operations (Orkes)
      class GroupResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Create or update a group
        def upsert_group(body, id)
          @api_client.call_api('/groups/{id}', 'PUT', path_params: { id: id }, body: body, return_type: 'Group', return_http_data_only: true)
        end

        # Get a group by ID
        def get_group(id)
          @api_client.call_api('/groups/{id}', 'GET', path_params: { id: id }, return_type: 'Group', return_http_data_only: true)
        end

        # List all groups
        def list_groups
          @api_client.call_api('/groups', 'GET', return_type: 'Array<Group>', return_http_data_only: true)
        end

        # Delete a group
        def delete_group(id)
          @api_client.call_api('/groups/{id}', 'DELETE', path_params: { id: id }, return_http_data_only: true)
        end

        # Add a user to a group
        def add_user_to_group(group_id, user_id)
          @api_client.call_api('/groups/{groupId}/users/{userId}', 'POST', path_params: { groupId: group_id, userId: user_id }, return_http_data_only: true)
        end

        # Get users in a group
        def get_users_in_group(id)
          @api_client.call_api('/groups/{id}/users', 'GET', path_params: { id: id }, return_type: 'Array<ConductorUser>', return_http_data_only: true)
        end

        # Remove a user from a group
        def remove_user_from_group(group_id, user_id)
          @api_client.call_api('/groups/{groupId}/users/{userId}', 'DELETE', path_params: { groupId: group_id, userId: user_id }, return_http_data_only: true)
        end

        # Add multiple users to a group
        def add_users_to_group(group_id, user_ids)
          @api_client.call_api('/groups/{groupId}/users', 'POST', path_params: { groupId: group_id }, body: user_ids, return_http_data_only: true)
        end

        # Remove multiple users from a group
        def remove_users_from_group(group_id, user_ids)
          @api_client.call_api('/groups/{groupId}/users', 'DELETE', path_params: { groupId: group_id }, body: user_ids, return_http_data_only: true)
        end

        # Get granted permissions for a group
        def get_granted_permissions(group_id)
          @api_client.call_api('/groups/{groupId}/permissions', 'GET', path_params: { groupId: group_id }, return_type: 'Object', return_http_data_only: true)
        end
      end
    end
  end
end

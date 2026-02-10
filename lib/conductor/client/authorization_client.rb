# frozen_string_literal: true

module Conductor
  module Client
    # AuthorizationClient - High-level client for authorization operations (Orkes)
    # Delegates to 6 resource APIs: application, user, group, authorization, role, token, gateway_auth
    class AuthorizationClient
      def initialize(api_client)
        @application_api = Http::Api::ApplicationResourceApi.new(api_client)
        @user_api = Http::Api::UserResourceApi.new(api_client)
        @group_api = Http::Api::GroupResourceApi.new(api_client)
        @authorization_api = Http::Api::AuthorizationResourceApi.new(api_client)
        @role_api = Http::Api::RoleResourceApi.new(api_client)
        @token_api = Http::Api::TokenResourceApi.new(api_client)
        @gateway_auth_api = Http::Api::GatewayAuthResourceApi.new(api_client)
      end

      # === Applications ===

      def create_application(request)
        @application_api.create_application(request)
      end

      def get_application(application_id)
        @application_api.get_application(application_id)
      end

      def list_applications
        @application_api.list_applications
      end

      def update_application(request, application_id)
        @application_api.update_application(request, application_id)
      end

      def delete_application(application_id)
        @application_api.delete_application(application_id)
      end

      def add_role_to_application_user(application_id, role)
        @application_api.add_role_to_application_user(application_id, role)
      end

      def remove_role_from_application_user(application_id, role)
        @application_api.remove_role_from_application_user(application_id, role)
      end

      def set_application_tags(tags, application_id)
        @application_api.put_tags_for_application(tags, application_id)
      end

      def get_application_tags(application_id)
        @application_api.get_tags_for_application(application_id)
      end

      def delete_application_tags(tags, application_id)
        @application_api.delete_tags_for_application(tags, application_id)
      end

      def create_access_key(application_id)
        @application_api.create_access_key(application_id)
      end

      def get_access_keys(application_id)
        @application_api.get_access_keys(application_id)
      end

      def toggle_access_key_status(application_id, key_id)
        @application_api.toggle_access_key_status(application_id, key_id)
      end

      def delete_access_key(application_id, key_id)
        @application_api.delete_access_key(application_id, key_id)
      end

      def get_app_by_access_key_id(access_key_id)
        @application_api.get_app_by_access_key_id(access_key_id)
      end

      # === Users ===

      def upsert_user(request, user_id)
        @user_api.upsert_user(request, user_id)
      end

      def get_user(user_id)
        @user_api.get_user(user_id)
      end

      def list_users(apps: false)
        @user_api.list_users(apps: apps)
      end

      def delete_user(user_id)
        @user_api.delete_user(user_id)
      end

      def check_permissions(user_id, target_type, target_id)
        @user_api.check_permissions(user_id, target_type, target_id)
      end

      def get_granted_permissions_for_user(user_id)
        @user_api.get_granted_permissions(user_id)
      end

      # === Groups ===

      def upsert_group(request, group_id)
        @group_api.upsert_group(request, group_id)
      end

      def get_group(group_id)
        @group_api.get_group(group_id)
      end

      def list_groups
        @group_api.list_groups
      end

      def delete_group(group_id)
        @group_api.delete_group(group_id)
      end

      def add_user_to_group(group_id, user_id)
        @group_api.add_user_to_group(group_id, user_id)
      end

      def get_users_in_group(group_id)
        @group_api.get_users_in_group(group_id)
      end

      def remove_user_from_group(group_id, user_id)
        @group_api.remove_user_from_group(group_id, user_id)
      end

      def add_users_to_group(group_id, user_ids)
        @group_api.add_users_to_group(group_id, user_ids)
      end

      def remove_users_from_group(group_id, user_ids)
        @group_api.remove_users_from_group(group_id, user_ids)
      end

      def get_granted_permissions_for_group(group_id)
        @group_api.get_granted_permissions(group_id)
      end

      # === Permissions ===

      def grant_permissions(subject, target, access)
        request = Http::Models::AuthorizationRequest.new(
          subject: subject, target: target, access: access
        )
        @authorization_api.grant_permissions(request)
      end

      def get_permissions(target)
        @authorization_api.get_permissions(target.type, target.id)
      end

      def remove_permissions(subject, target, access)
        request = Http::Models::AuthorizationRequest.new(
          subject: subject, target: target, access: access
        )
        @authorization_api.remove_permissions(request)
      end

      # === Tokens ===

      def generate_token(key_id, key_secret)
        request = Http::Models::GenerateTokenRequest.new(
          key_id: key_id, key_secret: key_secret
        )
        @token_api.generate_token(request)
      end

      def get_user_info_from_token
        @token_api.get_user_info
      end

      # === Roles ===

      def list_all_roles
        @role_api.list_all_roles
      end

      def list_system_roles
        @role_api.list_system_roles
      end

      def list_custom_roles
        @role_api.list_custom_roles
      end

      def list_available_permissions
        @role_api.list_available_permissions
      end

      def create_role(request)
        @role_api.create_role(request)
      end

      def get_role(role_name)
        @role_api.get_role(role_name)
      end

      def update_role(role_name, request)
        @role_api.update_role(role_name, request)
      end

      def delete_role(role_name)
        @role_api.delete_role(role_name)
      end

      # === Gateway Auth Config ===

      def create_gateway_auth_config(auth_config)
        @gateway_auth_api.create_config(auth_config)
      end

      def get_gateway_auth_config(config_id)
        @gateway_auth_api.get_config(config_id)
      end

      def list_gateway_auth_configs
        @gateway_auth_api.list_configs
      end

      def update_gateway_auth_config(config_id, auth_config)
        @gateway_auth_api.update_config(config_id, auth_config)
      end

      def delete_gateway_auth_config(config_id)
        @gateway_auth_api.delete_config(config_id)
      end
    end
  end
end

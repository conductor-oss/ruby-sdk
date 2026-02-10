# frozen_string_literal: true

module Conductor
  module Client
    # SecretClient - High-level client for secret management operations (Orkes)
    class SecretClient
      def initialize(api_client)
        @secret_api = Http::Api::SecretResourceApi.new(api_client)
      end

      def put_secret(key, value)
        @secret_api.put_secret(value, key)
      end

      def get_secret(key)
        @secret_api.get_secret(key)
      end

      def list_all_secret_names
        @secret_api.list_all_secret_names
      end

      def list_secrets_that_user_can_grant_access_to
        @secret_api.list_secrets_that_user_can_grant_access_to
      end

      def delete_secret(key)
        @secret_api.delete_secret(key)
      end

      def secret_exists(key)
        @secret_api.secret_exists(key)
      end

      def set_secret_tags(tags, key)
        @secret_api.put_tag_for_secret(tags, key)
      end

      def get_secret_tags(key)
        @secret_api.get_tags(key)
      end

      def delete_secret_tags(tags, key)
        @secret_api.delete_tag_for_secret(tags, key)
      end
    end
  end
end

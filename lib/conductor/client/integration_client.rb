# frozen_string_literal: true

module Conductor
  module Client
    # IntegrationClient - High-level client for integration management operations (Orkes)
    class IntegrationClient
      def initialize(api_client)
        @integration_api = Http::Api::IntegrationResourceApi.new(api_client)
      end

      # === Integration Providers ===

      def save_integration(integration_name, integration_details)
        @integration_api.save_integration(integration_details, integration_name)
      end

      def get_integration(integration_name)
        @integration_api.get_integration(integration_name)
      end

      def get_integrations
        @integration_api.get_integrations
      end

      def delete_integration(integration_name)
        @integration_api.delete_integration(integration_name)
      end

      # === Integration APIs ===

      def save_integration_api(integration_name, api_name, api_details)
        @integration_api.save_integration_api(api_details, integration_name, api_name)
      end

      def get_integration_api(api_name, integration_name)
        @integration_api.get_integration_api(integration_name, api_name)
      end

      def get_integration_apis(integration_name)
        @integration_api.get_integration_apis(integration_name)
      end

      def delete_integration_api(api_name, integration_name)
        @integration_api.delete_integration_api(integration_name, api_name)
      end

      # === Prompts ===

      def associate_prompt_with_integration(ai_integration, model_name, prompt_name)
        @integration_api.associate_prompt_with_integration(ai_integration, model_name, prompt_name)
      end

      def get_prompts_with_integration(ai_integration, model_name)
        @integration_api.get_prompts_with_integration(ai_integration, model_name)
      end

      # === Token Usage ===

      def get_token_usage_for_integration(name, integration_name)
        @integration_api.get_token_usage_for_integration(name, integration_name)
      end

      def get_token_usage_for_integration_provider(name)
        @integration_api.get_token_usage_for_integration_provider(name)
      end

      # === Tags ===

      def put_tag_for_integration(body, name, integration_name)
        @integration_api.put_tag_for_integration(body, name, integration_name)
      end

      def get_tags_for_integration(name, integration_name)
        @integration_api.get_tags_for_integration(name, integration_name)
      end

      def delete_tag_for_integration(body, name, integration_name)
        @integration_api.delete_tag_for_integration(body, name, integration_name)
      end

      def put_tag_for_integration_provider(body, name)
        @integration_api.put_tag_for_integration_provider(body, name)
      end

      def get_tags_for_integration_provider(name)
        @integration_api.get_tags_for_integration_provider(name)
      end

      def delete_tag_for_integration_provider(body, name)
        @integration_api.delete_tag_for_integration_provider(body, name)
      end

      # === Discovery ===

      def get_integration_available_apis(integration_name)
        @integration_api.get_integration_available_apis(integration_name)
      end

      def get_integration_provider_defs
        @integration_api.get_integration_provider_defs
      end

      def get_providers_and_integrations
        @integration_api.get_providers_and_integrations
      end
    end
  end
end

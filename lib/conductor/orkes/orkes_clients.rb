# frozen_string_literal: true

module Conductor
  module Orkes
    # OrkesClients - Factory class that creates all high-level clients from a single configuration
    # This is the primary entry point for Orkes Conductor users.
    #
    # Usage:
    #   config = Conductor::Configuration.new
    #   config.server_url = 'https://developer.orkescloud.com/api'
    #   config.authentication_settings = Conductor::Configuration::AuthenticationSettings.new(
    #     key_id: 'your_key', key_secret: 'your_secret'
    #   )
    #   clients = Conductor::Orkes::OrkesClients.new(config)
    #
    #   workflow_client = clients.get_workflow_client
    #   task_client = clients.get_task_client
    #   secret_client = clients.get_secret_client
    #
    class OrkesClients
      attr_reader :configuration, :api_client

      def initialize(configuration = nil)
        @configuration = configuration || Configuration.new
        @api_client = Http::ApiClient.new(configuration: @configuration)
      end

      def get_workflow_client
        Client::WorkflowClient.new(@configuration)
      end

      def get_task_client
        Client::TaskClient.new(@configuration)
      end

      def get_metadata_client
        Client::MetadataClient.new(@configuration)
      end

      def get_scheduler_client
        Client::SchedulerClient.new(@configuration)
      end

      def get_authorization_client
        Client::AuthorizationClient.new(@api_client)
      end

      def get_secret_client
        Client::SecretClient.new(@api_client)
      end

      def get_integration_client
        Client::IntegrationClient.new(@api_client)
      end

      def get_prompt_client
        Client::PromptClient.new(@api_client)
      end

      def get_schema_client
        Client::SchemaClient.new(@api_client)
      end

      def get_workflow_executor
        Workflow::WorkflowExecutor.new(@configuration)
      end
    end
  end
end

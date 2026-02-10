# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Orkes::OrkesClients do
  subject(:clients) { described_class.new(configuration) }

  let(:configuration) { Conductor::Configuration.new }
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }

  before do
    allow(Conductor::Http::ApiClient).to receive(:new).with(configuration: configuration).and_return(api_client)
  end

  describe '#initialize' do
    it 'stores configuration and creates api_client' do
      expect(clients.configuration).to eq(configuration)
      expect(clients.api_client).to eq(api_client)
    end

    it 'uses default configuration when none provided' do
      allow(Conductor::Http::ApiClient).to receive(:new).and_return(api_client)
      default_clients = described_class.new
      expect(default_clients.configuration).to be_a(Conductor::Configuration)
    end
  end

  describe '#get_workflow_client' do
    it 'returns a WorkflowClient' do
      result = clients.get_workflow_client
      expect(result).to be_a(Conductor::Client::WorkflowClient)
    end
  end

  describe '#get_task_client' do
    it 'returns a TaskClient' do
      result = clients.get_task_client
      expect(result).to be_a(Conductor::Client::TaskClient)
    end
  end

  describe '#get_metadata_client' do
    it 'returns a MetadataClient' do
      result = clients.get_metadata_client
      expect(result).to be_a(Conductor::Client::MetadataClient)
    end
  end

  describe '#get_scheduler_client' do
    it 'returns a SchedulerClient' do
      result = clients.get_scheduler_client
      expect(result).to be_a(Conductor::Client::SchedulerClient)
    end
  end

  describe '#get_authorization_client' do
    it 'returns an AuthorizationClient' do
      result = clients.get_authorization_client
      expect(result).to be_a(Conductor::Client::AuthorizationClient)
    end
  end

  describe '#get_secret_client' do
    it 'returns a SecretClient' do
      result = clients.get_secret_client
      expect(result).to be_a(Conductor::Client::SecretClient)
    end
  end

  describe '#get_integration_client' do
    it 'returns an IntegrationClient' do
      result = clients.get_integration_client
      expect(result).to be_a(Conductor::Client::IntegrationClient)
    end
  end

  describe '#get_prompt_client' do
    it 'returns a PromptClient' do
      result = clients.get_prompt_client
      expect(result).to be_a(Conductor::Client::PromptClient)
    end
  end

  describe '#get_schema_client' do
    it 'returns a SchemaClient' do
      result = clients.get_schema_client
      expect(result).to be_a(Conductor::Client::SchemaClient)
    end
  end

  describe '#get_workflow_executor' do
    it 'returns a WorkflowExecutor' do
      result = clients.get_workflow_executor
      expect(result).to be_a(Conductor::Workflow::WorkflowExecutor)
    end
  end

  describe 'client sharing' do
    it 'creates different client instances on each call' do
      client1 = clients.get_secret_client
      client2 = clients.get_secret_client
      expect(client1).not_to equal(client2)
    end

    it 'OSS clients receive configuration, Orkes clients receive api_client' do
      # OSS clients are created with configuration (they create their own ApiClient)
      expect(Conductor::Client::WorkflowClient).to receive(:new).with(configuration).and_call_original
      clients.get_workflow_client

      # Orkes clients receive the shared api_client
      expect(Conductor::Client::SecretClient).to receive(:new).with(api_client).and_call_original
      clients.get_secret_client
    end
  end
end

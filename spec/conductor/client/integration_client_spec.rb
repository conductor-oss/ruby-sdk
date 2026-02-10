# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Client::IntegrationClient do
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }
  let(:integration_api) { instance_double(Conductor::Http::Api::IntegrationResourceApi) }
  let(:client) { described_class.new(api_client) }

  before do
    allow(Conductor::Http::Api::IntegrationResourceApi).to receive(:new).with(api_client).and_return(integration_api)
  end

  # === Integration Providers ===

  describe '#save_integration' do
    it 'delegates with swapped args (details, name) to API' do
      details = double('details')
      expect(integration_api).to receive(:save_integration).with(details, 'openai')
      client.save_integration('openai', details)
    end
  end

  describe '#get_integration' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_integration).with('openai')
      client.get_integration('openai')
    end
  end

  describe '#get_integrations' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_integrations).and_return([])
      result = client.get_integrations
      expect(result).to eq([])
    end
  end

  describe '#delete_integration' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:delete_integration).with('old_provider')
      client.delete_integration('old_provider')
    end
  end

  # === Integration APIs ===

  describe '#save_integration_api' do
    it 'delegates with reordered args (details, name, integration_name) to API' do
      details = double('details')
      expect(integration_api).to receive(:save_integration_api).with(details, 'openai', 'gpt-4')
      client.save_integration_api('openai', 'gpt-4', details)
    end
  end

  describe '#get_integration_api' do
    it 'delegates with swapped args to API' do
      expect(integration_api).to receive(:get_integration_api).with('openai', 'gpt-4')
      client.get_integration_api('gpt-4', 'openai')
    end
  end

  describe '#get_integration_apis' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_integration_apis).with('openai').and_return([])
      client.get_integration_apis('openai')
    end
  end

  describe '#delete_integration_api' do
    it 'delegates with swapped args to API' do
      expect(integration_api).to receive(:delete_integration_api).with('openai', 'gpt-4')
      client.delete_integration_api('gpt-4', 'openai')
    end
  end

  # === Prompts ===

  describe '#associate_prompt_with_integration' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:associate_prompt_with_integration).with('openai', 'gpt-4', 'my_prompt')
      client.associate_prompt_with_integration('openai', 'gpt-4', 'my_prompt')
    end
  end

  describe '#get_prompts_with_integration' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_prompts_with_integration).with('openai', 'gpt-4').and_return([])
      client.get_prompts_with_integration('openai', 'gpt-4')
    end
  end

  # === Token Usage ===

  describe '#get_token_usage_for_integration' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_token_usage_for_integration).with('openai', 'gpt-4').and_return(1000)
      result = client.get_token_usage_for_integration('openai', 'gpt-4')
      expect(result).to eq(1000)
    end
  end

  describe '#get_token_usage_for_integration_provider' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_token_usage_for_integration_provider).with('openai')
      client.get_token_usage_for_integration_provider('openai')
    end
  end

  # === Tags ===

  describe '#put_tag_for_integration' do
    it 'delegates to integration_api' do
      body = [double('tag')]
      expect(integration_api).to receive(:put_tag_for_integration).with(body, 'openai', 'gpt-4')
      client.put_tag_for_integration(body, 'openai', 'gpt-4')
    end
  end

  describe '#get_tags_for_integration' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_tags_for_integration).with('openai', 'gpt-4').and_return([])
      client.get_tags_for_integration('openai', 'gpt-4')
    end
  end

  describe '#delete_tag_for_integration' do
    it 'delegates to integration_api' do
      body = [double('tag')]
      expect(integration_api).to receive(:delete_tag_for_integration).with(body, 'openai', 'gpt-4')
      client.delete_tag_for_integration(body, 'openai', 'gpt-4')
    end
  end

  describe '#put_tag_for_integration_provider' do
    it 'delegates to integration_api' do
      body = [double('tag')]
      expect(integration_api).to receive(:put_tag_for_integration_provider).with(body, 'openai')
      client.put_tag_for_integration_provider(body, 'openai')
    end
  end

  describe '#get_tags_for_integration_provider' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_tags_for_integration_provider).with('openai').and_return([])
      client.get_tags_for_integration_provider('openai')
    end
  end

  describe '#delete_tag_for_integration_provider' do
    it 'delegates to integration_api' do
      body = [double('tag')]
      expect(integration_api).to receive(:delete_tag_for_integration_provider).with(body, 'openai')
      client.delete_tag_for_integration_provider(body, 'openai')
    end
  end

  # === Discovery ===

  describe '#get_integration_available_apis' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_integration_available_apis).with('openai').and_return([])
      client.get_integration_available_apis('openai')
    end
  end

  describe '#get_integration_provider_defs' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_integration_provider_defs)
      client.get_integration_provider_defs
    end
  end

  describe '#get_providers_and_integrations' do
    it 'delegates to integration_api' do
      expect(integration_api).to receive(:get_providers_and_integrations).and_return([])
      client.get_providers_and_integrations
    end
  end
end

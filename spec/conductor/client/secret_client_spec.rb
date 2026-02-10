# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Client::SecretClient do
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }
  let(:secret_api) { instance_double(Conductor::Http::Api::SecretResourceApi) }
  let(:client) { described_class.new(api_client) }

  before do
    allow(Conductor::Http::Api::SecretResourceApi).to receive(:new).with(api_client).and_return(secret_api)
  end

  describe '#put_secret' do
    it 'delegates to secret_api with swapped args (value, key)' do
      expect(secret_api).to receive(:put_secret).with('my_value', 'my_key')
      client.put_secret('my_key', 'my_value')
    end
  end

  describe '#get_secret' do
    it 'delegates to secret_api' do
      expect(secret_api).to receive(:get_secret).with('db_password').and_return('s3cret')
      result = client.get_secret('db_password')
      expect(result).to eq('s3cret')
    end
  end

  describe '#list_all_secret_names' do
    it 'delegates to secret_api' do
      expect(secret_api).to receive(:list_all_secret_names).and_return(%w[secret1 secret2])
      result = client.list_all_secret_names
      expect(result).to eq(%w[secret1 secret2])
    end
  end

  describe '#list_secrets_that_user_can_grant_access_to' do
    it 'delegates to secret_api' do
      expect(secret_api).to receive(:list_secrets_that_user_can_grant_access_to).and_return(['s1'])
      result = client.list_secrets_that_user_can_grant_access_to
      expect(result).to eq(['s1'])
    end
  end

  describe '#delete_secret' do
    it 'delegates to secret_api' do
      expect(secret_api).to receive(:delete_secret).with('old_secret')
      client.delete_secret('old_secret')
    end
  end

  describe '#secret_exists' do
    it 'delegates to secret_api' do
      expect(secret_api).to receive(:secret_exists).with('my_key').and_return(true)
      result = client.secret_exists('my_key')
      expect(result).to eq(true)
    end
  end

  describe '#set_secret_tags' do
    it 'delegates to put_tag_for_secret' do
      tags = [Conductor::Http::Models::TagObject.new(key: 'env', value: 'prod')]
      expect(secret_api).to receive(:put_tag_for_secret).with(tags, 'my_key')
      client.set_secret_tags(tags, 'my_key')
    end
  end

  describe '#get_secret_tags' do
    it 'delegates to get_tags' do
      expect(secret_api).to receive(:get_tags).with('my_key').and_return([])
      result = client.get_secret_tags('my_key')
      expect(result).to eq([])
    end
  end

  describe '#delete_secret_tags' do
    it 'delegates to delete_tag_for_secret' do
      tags = [Conductor::Http::Models::TagObject.new(key: 'env')]
      expect(secret_api).to receive(:delete_tag_for_secret).with(tags, 'my_key')
      client.delete_secret_tags(tags, 'my_key')
    end
  end
end

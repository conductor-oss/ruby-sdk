# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Client::SchemaClient do
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }
  let(:schema_api) { instance_double(Conductor::Http::Api::SchemaResourceApi) }
  let(:client) { described_class.new(api_client) }

  before do
    allow(Conductor::Http::Api::SchemaResourceApi).to receive(:new).with(api_client).and_return(schema_api)
  end

  describe '#register_schema' do
    it 'delegates to save with default new_version=false' do
      schema = double('schema')
      expect(schema_api).to receive(:save).with(schema, new_version: false)
      client.register_schema(schema)
    end

    it 'passes new_version parameter' do
      schema = double('schema')
      expect(schema_api).to receive(:save).with(schema, new_version: true)
      client.register_schema(schema, new_version: true)
    end
  end

  describe '#get_schema' do
    it 'delegates to get_schema_by_name_and_version' do
      expect(schema_api).to receive(:get_schema_by_name_and_version).with('my_schema', 1)
      client.get_schema('my_schema', 1)
    end
  end

  describe '#get_all_schemas' do
    it 'delegates to schema_api' do
      expect(schema_api).to receive(:get_all_schemas).and_return([])
      result = client.get_all_schemas
      expect(result).to eq([])
    end
  end

  describe '#delete_schema' do
    it 'delegates to delete_schema_by_name_and_version' do
      expect(schema_api).to receive(:delete_schema_by_name_and_version).with('old_schema', 2)
      client.delete_schema('old_schema', 2)
    end
  end

  describe '#delete_schema_by_name' do
    it 'delegates to schema_api' do
      expect(schema_api).to receive(:delete_schema_by_name).with('obsolete_schema')
      client.delete_schema_by_name('obsolete_schema')
    end
  end
end

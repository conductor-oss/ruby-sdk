# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Worker::TaskDefinitionRegistrar do
  let(:configuration) do
    Conductor::Configuration.new(server_api_url: 'http://localhost:8080/api')
  end

  let(:logger) do
    Logger.new(nil) # Suppress output in tests
  end

  let(:registrar) { described_class.new(configuration, logger: logger) }

  describe '#initialize' do
    it 'creates a registrar with configuration' do
      expect(registrar).to be_a(described_class)
    end
  end

  describe '#register' do
    context 'when worker.register_task_def is false' do
      it 'returns false without registering' do
        worker = Conductor::Worker::Worker.new('test_task', register_task_def: false) { {} }
        result = registrar.register(worker)
        expect(result).to be false
      end
    end

    context 'when worker.register_task_def is true' do
      # Note: These tests would require mocking the MetadataClient
      # For now, we test the schema generation logic
    end
  end
end

RSpec.describe Conductor::Worker::JsonSchemaGenerator do
  describe '.from_value' do
    it 'generates string schema for String' do
      schema = described_class.from_value('hello')
      expect(schema).to eq({ 'type' => 'string' })
    end

    it 'generates integer schema for Integer' do
      schema = described_class.from_value(42)
      expect(schema).to eq({ 'type' => 'integer' })
    end

    it 'generates number schema for Float' do
      schema = described_class.from_value(3.14)
      expect(schema).to eq({ 'type' => 'number' })
    end

    it 'generates boolean schema for true' do
      schema = described_class.from_value(true)
      expect(schema).to eq({ 'type' => 'boolean' })
    end

    it 'generates boolean schema for false' do
      schema = described_class.from_value(false)
      expect(schema).to eq({ 'type' => 'boolean' })
    end

    it 'generates null schema for nil' do
      schema = described_class.from_value(nil)
      expect(schema).to eq({ 'type' => 'null' })
    end

    it 'generates array schema for empty Array' do
      schema = described_class.from_value([])
      expect(schema).to eq({ 'type' => 'array' })
    end

    it 'generates array schema with items for non-empty Array' do
      schema = described_class.from_value([1, 2, 3])
      expect(schema).to eq({ 'type' => 'array', 'items' => { 'type' => 'integer' } })
    end

    it 'generates object schema for Hash' do
      schema = described_class.from_value({ 'name' => 'Alice', 'age' => 30 })
      expect(schema).to eq({
        'type' => 'object',
        'properties' => {
          'name' => { 'type' => 'string' },
          'age' => { 'type' => 'integer' }
        }
      })
    end

    it 'generates date-time string schema for Time' do
      schema = described_class.from_value(Time.now)
      expect(schema).to eq({ 'type' => 'string', 'format' => 'date-time' })
    end

    it 'generates date string schema for Date' do
      schema = described_class.from_value(Date.today)
      expect(schema).to eq({ 'type' => 'string', 'format' => 'date' })
    end
  end

  describe '.generate_object_schema' do
    it 'generates schema from hash with sample values' do
      sample = {
        'user_id' => 123,
        'email' => 'user@example.com',
        'active' => true,
        'tags' => ['admin', 'user']
      }

      schema = described_class.generate_object_schema(sample)

      expect(schema['type']).to eq('object')
      expect(schema['properties']['user_id']).to eq({ 'type' => 'integer' })
      expect(schema['properties']['email']).to eq({ 'type' => 'string' })
      expect(schema['properties']['active']).to eq({ 'type' => 'boolean' })
      expect(schema['properties']['tags']).to eq({ 'type' => 'array', 'items' => { 'type' => 'string' } })
    end
  end

  describe '.from_class' do
    it 'generates schema from Struct' do
      user_struct = Struct.new(:name, :email, :age)
      schema = described_class.from_class(user_struct)

      expect(schema['$schema']).to eq('http://json-schema.org/draft-07/schema#')
      expect(schema['type']).to eq('object')
      expect(schema['properties'].keys).to contain_exactly('name', 'email', 'age')
    end
  end
end

# Test the input schema generation from worker parameters
RSpec.describe 'Worker Input Schema Generation' do
  let(:configuration) do
    Conductor::Configuration.new(server_api_url: 'http://localhost:8080/api')
  end

  let(:registrar) { Conductor::Worker::TaskDefinitionRegistrar.new(configuration) }

  describe 'infer_property_schema (via private method)' do
    # We test the naming convention inference indirectly through workers

    it 'infers integer for *_id parameters' do
      worker = Conductor::Worker::Worker.new('test', register_task_def: true) do |user_id:|
        { id: user_id }
      end

      # Access private method for testing
      schema = registrar.send(:generate_input_schema, worker)

      expect(schema['properties']['user_id']['type']).to eq('integer')
    end

    it 'infers boolean for is_* parameters' do
      worker = Conductor::Worker::Worker.new('test', register_task_def: true) do |is_active:|
        { active: is_active }
      end

      schema = registrar.send(:generate_input_schema, worker)

      expect(schema['properties']['is_active']['type']).to eq('boolean')
    end

    it 'infers array for *_list parameters' do
      worker = Conductor::Worker::Worker.new('test', register_task_def: true) do |user_list:|
        { users: user_list }
      end

      schema = registrar.send(:generate_input_schema, worker)

      expect(schema['properties']['user_list']['type']).to eq('array')
    end

    it 'infers object for *_data parameters' do
      worker = Conductor::Worker::Worker.new('test', register_task_def: true) do |user_data:|
        { data: user_data }
      end

      schema = registrar.send(:generate_input_schema, worker)

      expect(schema['properties']['user_data']['type']).to eq('object')
    end

    it 'adds email format for email parameters' do
      worker = Conductor::Worker::Worker.new('test', register_task_def: true) do |email:|
        { email: email }
      end

      schema = registrar.send(:generate_input_schema, worker)

      expect(schema['properties']['email']['format']).to eq('email')
    end

    it 'marks required keyword args as required' do
      worker = Conductor::Worker::Worker.new('test', register_task_def: true) do |required_param:, optional_param: nil|
        { req: required_param, opt: optional_param }
      end

      schema = registrar.send(:generate_input_schema, worker)

      expect(schema['required']).to include('required_param')
      expect(schema['required']).not_to include('optional_param')
    end

    it 'returns nil for workers that take task object directly' do
      worker = Conductor::Worker::Worker.new('test', register_task_def: true) do |task|
        { result: task.input_data }
      end

      schema = registrar.send(:generate_input_schema, worker)

      expect(schema).to be_nil
    end
  end
end

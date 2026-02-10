# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Http::Models::TagObject do
  it 'creates a tag with key, type, and value' do
    tag = described_class.new(key: 'env', type: 'METADATA', value: 'prod')
    expect(tag.key).to eq('env')
    expect(tag.type).to eq('METADATA')
    expect(tag.value).to eq('prod')
  end

  it 'serializes to hash' do
    tag = described_class.new(key: 'k', type: 'RATE_LIMIT', value: 100)
    hash = tag.to_h
    expect(hash).to eq({ 'key' => 'k', 'type' => 'RATE_LIMIT', 'value' => 100 })
  end

  it 'omits nil fields from hash' do
    tag = described_class.new(key: 'k')
    hash = tag.to_h
    expect(hash).to eq({ 'key' => 'k' })
    expect(hash).not_to have_key('type')
    expect(hash).not_to have_key('value')
  end

  it 'deserializes from hash' do
    hash = { 'key' => 'env', 'type' => 'METADATA', 'value' => 'staging' }
    tag = described_class.from_hash(hash)
    expect(tag.key).to eq('env')
    expect(tag.type).to eq('METADATA')
    expect(tag.value).to eq('staging')
  end
end

RSpec.describe Conductor::Http::Models::TagType do
  it 'defines METADATA' do
    expect(described_class::METADATA).to eq('METADATA')
  end

  it 'defines RATE_LIMIT' do
    expect(described_class::RATE_LIMIT).to eq('RATE_LIMIT')
  end
end

RSpec.describe Conductor::Http::Models::SubjectRef do
  it 'creates with type and id' do
    ref = described_class.new(type: Conductor::Http::Models::SubjectType::USER, id: 'user-123')
    expect(ref.type).to eq('USER')
    expect(ref.id).to eq('user-123')
  end

  it 'serializes and deserializes correctly' do
    ref = described_class.new(type: 'GROUP', id: 'grp-1')
    hash = ref.to_h
    expect(hash).to eq({ 'type' => 'GROUP', 'id' => 'grp-1' })

    restored = described_class.from_hash(hash)
    expect(restored.type).to eq('GROUP')
    expect(restored.id).to eq('grp-1')
  end
end

RSpec.describe Conductor::Http::Models::SubjectType do
  it 'defines all subject types' do
    expect(described_class::USER).to eq('USER')
    expect(described_class::ROLE).to eq('ROLE')
    expect(described_class::GROUP).to eq('GROUP')
    expect(described_class::TAG).to eq('TAG')
  end
end

RSpec.describe Conductor::Http::Models::TargetRef do
  it 'creates with type and id' do
    ref = described_class.new(type: Conductor::Http::Models::TargetType::WORKFLOW_DEF, id: 'wf-1')
    expect(ref.type).to eq('WORKFLOW_DEF')
    expect(ref.id).to eq('wf-1')
  end

  it 'serializes and deserializes correctly' do
    ref = described_class.new(type: 'SECRET', id: 'my_secret')
    hash = ref.to_h
    expect(hash).to eq({ 'type' => 'SECRET', 'id' => 'my_secret' })

    restored = described_class.from_hash(hash)
    expect(restored.type).to eq('SECRET')
    expect(restored.id).to eq('my_secret')
  end
end

RSpec.describe Conductor::Http::Models::TargetType do
  it 'defines all target types' do
    expect(described_class::WORKFLOW_DEF).to eq('WORKFLOW_DEF')
    expect(described_class::TASK_DEF).to eq('TASK_DEF')
    expect(described_class::APPLICATION).to eq('APPLICATION')
    expect(described_class::USER).to eq('USER')
    expect(described_class::SECRET).to eq('SECRET')
    expect(described_class::SECRET_NAME).to eq('SECRET_NAME')
    expect(described_class::TAG).to eq('TAG')
    expect(described_class::DOMAIN).to eq('DOMAIN')
  end
end

RSpec.describe Conductor::Http::Models::AuthorizationRequest do
  it 'creates with subject, target, and access' do
    subject = Conductor::Http::Models::SubjectRef.new(type: 'USER', id: 'u1')
    target = Conductor::Http::Models::TargetRef.new(type: 'WORKFLOW_DEF', id: 'wf1')
    req = described_class.new(subject: subject, target: target, access: ['READ', 'EXECUTE'])

    expect(req.subject).to eq(subject)
    expect(req.target).to eq(target)
    expect(req.access).to eq(['READ', 'EXECUTE'])
  end

  it 'serializes nested models' do
    subject = Conductor::Http::Models::SubjectRef.new(type: 'GROUP', id: 'g1')
    target = Conductor::Http::Models::TargetRef.new(type: 'TASK_DEF', id: 't1')
    req = described_class.new(subject: subject, target: target, access: ['CREATE'])
    hash = req.to_h

    expect(hash['subject']).to eq({ 'type' => 'GROUP', 'id' => 'g1' })
    expect(hash['target']).to eq({ 'type' => 'TASK_DEF', 'id' => 't1' })
    expect(hash['access']).to eq(['CREATE'])
  end
end

RSpec.describe Conductor::Http::Models::AccessType do
  it 'defines all access types' do
    expect(described_class::CREATE).to eq('CREATE')
    expect(described_class::READ).to eq('READ')
    expect(described_class::UPDATE).to eq('UPDATE')
    expect(described_class::DELETE).to eq('DELETE')
    expect(described_class::EXECUTE).to eq('EXECUTE')
  end
end

RSpec.describe Conductor::Http::Models::SchemaDef do
  it 'creates with defaults' do
    schema = described_class.new(name: 'my_schema', type: Conductor::Http::Models::SchemaType::JSON)
    expect(schema.name).to eq('my_schema')
    expect(schema.type).to eq('JSON')
    expect(schema.version).to eq(1) # default
  end

  it 'allows overriding version' do
    schema = described_class.new(name: 's', version: 5)
    expect(schema.version).to eq(5)
  end

  it 'serializes with camelCase keys' do
    schema = described_class.new(
      name: 'test_schema', version: 2, type: 'AVRO',
      owner_app: 'my_app', created_by: 'admin',
      data: { 'field1' => 'string' }
    )
    hash = schema.to_h
    expect(hash['name']).to eq('test_schema')
    expect(hash['version']).to eq(2)
    expect(hash['type']).to eq('AVRO')
    expect(hash['ownerApp']).to eq('my_app')
    expect(hash['createdBy']).to eq('admin')
    expect(hash['data']).to eq({ 'field1' => 'string' })
  end

  it 'deserializes from camelCase hash' do
    hash = {
      'name' => 'deserialized_schema', 'version' => 3, 'type' => 'PROTOBUF',
      'ownerApp' => 'app1', 'createdBy' => 'user1', 'externalRef' => 'http://example.com'
    }
    schema = described_class.from_hash(hash)
    expect(schema.name).to eq('deserialized_schema')
    expect(schema.version).to eq(3)
    expect(schema.type).to eq('PROTOBUF')
    expect(schema.owner_app).to eq('app1')
    expect(schema.created_by).to eq('user1')
    expect(schema.external_ref).to eq('http://example.com')
  end
end

RSpec.describe Conductor::Http::Models::SchemaType do
  it 'defines all schema types' do
    expect(described_class::JSON).to eq('JSON')
    expect(described_class::AVRO).to eq('AVRO')
    expect(described_class::PROTOBUF).to eq('PROTOBUF')
  end
end

RSpec.describe Conductor::Http::Models::PromptTemplateTestRequest do
  it 'creates with all parameters' do
    req = described_class.new(
      llm_provider: 'openai',
      model: 'gpt-4',
      prompt: 'Hello ${name}',
      prompt_variables: { 'name' => 'World' },
      temperature: 0.7,
      top_p: 0.9,
      stop_words: ['END']
    )
    expect(req.llm_provider).to eq('openai')
    expect(req.model).to eq('gpt-4')
    expect(req.prompt).to eq('Hello ${name}')
    expect(req.prompt_variables).to eq({ 'name' => 'World' })
    expect(req.temperature).to eq(0.7)
    expect(req.top_p).to eq(0.9)
    expect(req.stop_words).to eq(['END'])
  end

  it 'serializes with camelCase keys' do
    req = described_class.new(
      llm_provider: 'azure', model: 'gpt-35-turbo',
      prompt: 'test', temperature: 0.5, top_p: 0.8
    )
    hash = req.to_h
    expect(hash['llmProvider']).to eq('azure')
    expect(hash['model']).to eq('gpt-35-turbo')
    expect(hash['prompt']).to eq('test')
    expect(hash['temperature']).to eq(0.5)
    expect(hash['topP']).to eq(0.8)
  end

  it 'deserializes from camelCase hash' do
    hash = {
      'llmProvider' => 'cohere', 'model' => 'command',
      'prompt' => 'Summarize:', 'promptVariables' => { 'text' => 'hello' },
      'stopWords' => ['STOP'], 'temperature' => 0.3, 'topP' => 0.95
    }
    req = described_class.from_hash(hash)
    expect(req.llm_provider).to eq('cohere')
    expect(req.model).to eq('command')
    expect(req.prompt_variables).to eq({ 'text' => 'hello' })
    expect(req.stop_words).to eq(['STOP'])
  end
end

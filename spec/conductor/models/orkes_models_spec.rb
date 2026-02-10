# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Orkes::Models::MetadataTag do
  it 'creates a tag with METADATA type' do
    tag = described_class.new(key: 'env', value: 'production')
    expect(tag.key).to eq('env')
    expect(tag.value).to eq('production')
    expect(tag.type).to eq(Conductor::Http::Models::TagType::METADATA)
  end

  it 'serializes to hash with correct JSON keys' do
    tag = described_class.new(key: 'team', value: 'platform')
    hash = tag.to_h
    expect(hash['key']).to eq('team')
    expect(hash['type']).to eq('METADATA')
    expect(hash['value']).to eq('platform')
  end

  it 'inherits from TagObject' do
    tag = described_class.new(key: 'k', value: 'v')
    expect(tag).to be_a(Conductor::Http::Models::TagObject)
    expect(tag).to be_a(Conductor::Http::Models::BaseModel)
  end
end

RSpec.describe Conductor::Orkes::Models::RateLimitTag do
  it 'creates a tag with RATE_LIMIT type' do
    tag = described_class.new(key: 'api_calls', value: 100)
    expect(tag.key).to eq('api_calls')
    expect(tag.value).to eq(100)
    expect(tag.type).to eq(Conductor::Http::Models::TagType::RATE_LIMIT)
  end

  it 'serializes to hash with correct JSON keys' do
    tag = described_class.new(key: 'requests', value: 50)
    hash = tag.to_h
    expect(hash['key']).to eq('requests')
    expect(hash['type']).to eq('RATE_LIMIT')
    expect(hash['value']).to eq(50)
  end
end

RSpec.describe Conductor::Orkes::Models::AccessKey do
  it 'creates an access key with default ACTIVE status' do
    key = described_class.new(id: 'key-123')
    expect(key.id).to eq('key-123')
    expect(key.status).to eq(Conductor::Orkes::Models::AccessKeyStatus::ACTIVE)
    expect(key.created_at).to be_nil
  end

  it 'allows overriding the status' do
    key = described_class.new(id: 'key-456', status: Conductor::Orkes::Models::AccessKeyStatus::INACTIVE)
    expect(key.status).to eq('INACTIVE')
  end

  it 'serializes to hash with camelCase keys' do
    key = described_class.new(id: 'key-789', status: 'ACTIVE', created_at: 1700000000)
    hash = key.to_h
    expect(hash['id']).to eq('key-789')
    expect(hash['status']).to eq('ACTIVE')
    expect(hash['createdAt']).to eq(1700000000)
  end

  it 'deserializes from hash with camelCase keys' do
    hash = { 'id' => 'key-abc', 'status' => 'INACTIVE', 'createdAt' => 1700000000 }
    key = described_class.from_hash(hash)
    expect(key.id).to eq('key-abc')
    expect(key.status).to eq('INACTIVE')
    expect(key.created_at).to eq(1700000000)
  end
end

RSpec.describe Conductor::Orkes::Models::CreatedAccessKey do
  it 'creates with id and secret' do
    key = described_class.new(id: 'key-new', secret: 's3cret!')
    expect(key.id).to eq('key-new')
    expect(key.secret).to eq('s3cret!')
  end

  it 'serializes to hash' do
    key = described_class.new(id: 'key-new', secret: 'shh')
    hash = key.to_h
    expect(hash['id']).to eq('key-new')
    expect(hash['secret']).to eq('shh')
  end

  it 'deserializes from hash' do
    hash = { 'id' => 'key-x', 'secret' => 'top-secret' }
    key = described_class.from_hash(hash)
    expect(key.id).to eq('key-x')
    expect(key.secret).to eq('top-secret')
  end
end

RSpec.describe Conductor::Orkes::Models::AccessKeyStatus do
  it 'defines ACTIVE constant' do
    expect(described_class::ACTIVE).to eq('ACTIVE')
  end

  it 'defines INACTIVE constant' do
    expect(described_class::INACTIVE).to eq('INACTIVE')
  end
end

RSpec.describe Conductor::Orkes::Models::GrantedPermission do
  it 'creates with target and access list' do
    target = Conductor::Http::Models::TargetRef.new(
      type: Conductor::Http::Models::TargetType::WORKFLOW_DEF,
      id: 'my_workflow'
    )
    perm = described_class.new(target: target, access: ['READ', 'EXECUTE'])
    expect(perm.target).to eq(target)
    expect(perm.access).to eq(['READ', 'EXECUTE'])
  end

  it 'serializes with nested target' do
    target = Conductor::Http::Models::TargetRef.new(
      type: Conductor::Http::Models::TargetType::TASK_DEF,
      id: 'my_task'
    )
    perm = described_class.new(target: target, access: ['CREATE'])
    hash = perm.to_h
    expect(hash['target']).to eq({ 'type' => 'TASK_DEF', 'id' => 'my_task' })
    expect(hash['access']).to eq(['CREATE'])
  end
end

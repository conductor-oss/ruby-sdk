# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Client::AuthorizationClient do
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }
  let(:application_api) { instance_double(Conductor::Http::Api::ApplicationResourceApi) }
  let(:user_api) { instance_double(Conductor::Http::Api::UserResourceApi) }
  let(:group_api) { instance_double(Conductor::Http::Api::GroupResourceApi) }
  let(:authorization_api) { instance_double(Conductor::Http::Api::AuthorizationResourceApi) }
  let(:role_api) { instance_double(Conductor::Http::Api::RoleResourceApi) }
  let(:token_api) { instance_double(Conductor::Http::Api::TokenResourceApi) }
  let(:gateway_auth_api) { instance_double(Conductor::Http::Api::GatewayAuthResourceApi) }
  let(:client) { described_class.new(api_client) }

  before do
    allow(Conductor::Http::Api::ApplicationResourceApi).to receive(:new).with(api_client).and_return(application_api)
    allow(Conductor::Http::Api::UserResourceApi).to receive(:new).with(api_client).and_return(user_api)
    allow(Conductor::Http::Api::GroupResourceApi).to receive(:new).with(api_client).and_return(group_api)
    allow(Conductor::Http::Api::AuthorizationResourceApi).to receive(:new).with(api_client).and_return(authorization_api)
    allow(Conductor::Http::Api::RoleResourceApi).to receive(:new).with(api_client).and_return(role_api)
    allow(Conductor::Http::Api::TokenResourceApi).to receive(:new).with(api_client).and_return(token_api)
    allow(Conductor::Http::Api::GatewayAuthResourceApi).to receive(:new).with(api_client).and_return(gateway_auth_api)
  end

  # === Applications ===

  describe '#create_application' do
    it 'delegates to application_api' do
      request = double('request')
      expect(application_api).to receive(:create_application).with(request)
      client.create_application(request)
    end
  end

  describe '#get_application' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:get_application).with('app-123')
      client.get_application('app-123')
    end
  end

  describe '#list_applications' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:list_applications).and_return([])
      result = client.list_applications
      expect(result).to eq([])
    end
  end

  describe '#update_application' do
    it 'delegates to application_api' do
      request = double('request')
      expect(application_api).to receive(:update_application).with(request, 'app-123')
      client.update_application(request, 'app-123')
    end
  end

  describe '#delete_application' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:delete_application).with('app-123')
      client.delete_application('app-123')
    end
  end

  describe '#add_role_to_application_user' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:add_role_to_application_user).with('app-1', 'ADMIN')
      client.add_role_to_application_user('app-1', 'ADMIN')
    end
  end

  describe '#remove_role_from_application_user' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:remove_role_from_application_user).with('app-1', 'USER')
      client.remove_role_from_application_user('app-1', 'USER')
    end
  end

  describe '#set_application_tags' do
    it 'delegates to put_tags_for_application' do
      tags = [double('tag')]
      expect(application_api).to receive(:put_tags_for_application).with(tags, 'app-1')
      client.set_application_tags(tags, 'app-1')
    end
  end

  describe '#get_application_tags' do
    it 'delegates to get_tags_for_application' do
      expect(application_api).to receive(:get_tags_for_application).with('app-1').and_return([])
      client.get_application_tags('app-1')
    end
  end

  describe '#delete_application_tags' do
    it 'delegates to delete_tags_for_application' do
      tags = [double('tag')]
      expect(application_api).to receive(:delete_tags_for_application).with(tags, 'app-1')
      client.delete_application_tags(tags, 'app-1')
    end
  end

  describe '#create_access_key' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:create_access_key).with('app-1')
      client.create_access_key('app-1')
    end
  end

  describe '#get_access_keys' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:get_access_keys).with('app-1').and_return([])
      client.get_access_keys('app-1')
    end
  end

  describe '#toggle_access_key_status' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:toggle_access_key_status).with('app-1', 'key-1')
      client.toggle_access_key_status('app-1', 'key-1')
    end
  end

  describe '#delete_access_key' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:delete_access_key).with('app-1', 'key-1')
      client.delete_access_key('app-1', 'key-1')
    end
  end

  describe '#get_app_by_access_key_id' do
    it 'delegates to application_api' do
      expect(application_api).to receive(:get_app_by_access_key_id).with('key-abc')
      client.get_app_by_access_key_id('key-abc')
    end
  end

  # === Users ===

  describe '#upsert_user' do
    it 'delegates to user_api' do
      request = double('request')
      expect(user_api).to receive(:upsert_user).with(request, 'user-1')
      client.upsert_user(request, 'user-1')
    end
  end

  describe '#get_user' do
    it 'delegates to user_api' do
      expect(user_api).to receive(:get_user).with('user-1')
      client.get_user('user-1')
    end
  end

  describe '#list_users' do
    it 'delegates to user_api with default apps=false' do
      expect(user_api).to receive(:list_users).with(apps: false).and_return([])
      client.list_users
    end

    it 'passes apps parameter' do
      expect(user_api).to receive(:list_users).with(apps: true).and_return([])
      client.list_users(apps: true)
    end
  end

  describe '#delete_user' do
    it 'delegates to user_api' do
      expect(user_api).to receive(:delete_user).with('user-1')
      client.delete_user('user-1')
    end
  end

  describe '#check_permissions' do
    it 'delegates to user_api' do
      expect(user_api).to receive(:check_permissions).with('user-1', 'WORKFLOW_DEF', 'wf-1')
      client.check_permissions('user-1', 'WORKFLOW_DEF', 'wf-1')
    end
  end

  describe '#get_granted_permissions_for_user' do
    it 'delegates to user_api' do
      expect(user_api).to receive(:get_granted_permissions).with('user-1')
      client.get_granted_permissions_for_user('user-1')
    end
  end

  # === Groups ===

  describe '#upsert_group' do
    it 'delegates to group_api' do
      request = double('request')
      expect(group_api).to receive(:upsert_group).with(request, 'grp-1')
      client.upsert_group(request, 'grp-1')
    end
  end

  describe '#get_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:get_group).with('grp-1')
      client.get_group('grp-1')
    end
  end

  describe '#list_groups' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:list_groups).and_return([])
      client.list_groups
    end
  end

  describe '#delete_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:delete_group).with('grp-1')
      client.delete_group('grp-1')
    end
  end

  describe '#add_user_to_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:add_user_to_group).with('grp-1', 'user-1')
      client.add_user_to_group('grp-1', 'user-1')
    end
  end

  describe '#get_users_in_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:get_users_in_group).with('grp-1').and_return([])
      client.get_users_in_group('grp-1')
    end
  end

  describe '#remove_user_from_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:remove_user_from_group).with('grp-1', 'user-1')
      client.remove_user_from_group('grp-1', 'user-1')
    end
  end

  describe '#add_users_to_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:add_users_to_group).with('grp-1', %w[u1 u2])
      client.add_users_to_group('grp-1', %w[u1 u2])
    end
  end

  describe '#remove_users_from_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:remove_users_from_group).with('grp-1', %w[u1 u2])
      client.remove_users_from_group('grp-1', %w[u1 u2])
    end
  end

  describe '#get_granted_permissions_for_group' do
    it 'delegates to group_api' do
      expect(group_api).to receive(:get_granted_permissions).with('grp-1')
      client.get_granted_permissions_for_group('grp-1')
    end
  end

  # === Permissions ===

  describe '#grant_permissions' do
    it 'constructs AuthorizationRequest and delegates' do
      subject = Conductor::Http::Models::SubjectRef.new(type: 'USER', id: 'u1')
      target = Conductor::Http::Models::TargetRef.new(type: 'WORKFLOW_DEF', id: 'wf1')
      access = %w[READ EXECUTE]

      expect(authorization_api).to receive(:grant_permissions) do |req|
        expect(req).to be_a(Conductor::Http::Models::AuthorizationRequest)
        expect(req.subject).to eq(subject)
        expect(req.target).to eq(target)
        expect(req.access).to eq(access)
      end

      client.grant_permissions(subject, target, access)
    end
  end

  describe '#get_permissions' do
    it 'extracts type and id from target' do
      target = Conductor::Http::Models::TargetRef.new(type: 'WORKFLOW_DEF', id: 'wf1')
      expect(authorization_api).to receive(:get_permissions).with('WORKFLOW_DEF', 'wf1')
      client.get_permissions(target)
    end
  end

  describe '#remove_permissions' do
    it 'constructs AuthorizationRequest and delegates' do
      subject = Conductor::Http::Models::SubjectRef.new(type: 'GROUP', id: 'g1')
      target = Conductor::Http::Models::TargetRef.new(type: 'TASK_DEF', id: 't1')
      access = ['DELETE']

      expect(authorization_api).to receive(:remove_permissions) do |req|
        expect(req).to be_a(Conductor::Http::Models::AuthorizationRequest)
        expect(req.subject).to eq(subject)
        expect(req.target).to eq(target)
        expect(req.access).to eq(access)
      end

      client.remove_permissions(subject, target, access)
    end
  end

  # === Tokens ===

  describe '#generate_token' do
    it 'constructs GenerateTokenRequest and delegates' do
      expect(token_api).to receive(:generate_token) do |req|
        expect(req).to be_a(Conductor::Http::Models::GenerateTokenRequest)
        expect(req.key_id).to eq('my_key')
        expect(req.key_secret).to eq('my_secret')
      end

      client.generate_token('my_key', 'my_secret')
    end
  end

  describe '#get_user_info_from_token' do
    it 'delegates to token_api' do
      expect(token_api).to receive(:get_user_info)
      client.get_user_info_from_token
    end
  end

  # === Roles ===

  describe '#list_all_roles' do
    it 'delegates to role_api' do
      expect(role_api).to receive(:list_all_roles).and_return([])
      client.list_all_roles
    end
  end

  describe '#list_system_roles' do
    it 'delegates to role_api' do
      expect(role_api).to receive(:list_system_roles)
      client.list_system_roles
    end
  end

  describe '#list_custom_roles' do
    it 'delegates to role_api' do
      expect(role_api).to receive(:list_custom_roles).and_return([])
      client.list_custom_roles
    end
  end

  describe '#list_available_permissions' do
    it 'delegates to role_api' do
      expect(role_api).to receive(:list_available_permissions)
      client.list_available_permissions
    end
  end

  describe '#create_role' do
    it 'delegates to role_api' do
      request = double('request')
      expect(role_api).to receive(:create_role).with(request)
      client.create_role(request)
    end
  end

  describe '#get_role' do
    it 'delegates to role_api' do
      expect(role_api).to receive(:get_role).with('admin')
      client.get_role('admin')
    end
  end

  describe '#update_role' do
    it 'delegates to role_api' do
      request = double('request')
      expect(role_api).to receive(:update_role).with('admin', request)
      client.update_role('admin', request)
    end
  end

  describe '#delete_role' do
    it 'delegates to role_api' do
      expect(role_api).to receive(:delete_role).with('old_role')
      client.delete_role('old_role')
    end
  end

  # === Gateway Auth Config ===

  describe '#create_gateway_auth_config' do
    it 'delegates to gateway_auth_api' do
      config = double('config')
      expect(gateway_auth_api).to receive(:create_config).with(config)
      client.create_gateway_auth_config(config)
    end
  end

  describe '#get_gateway_auth_config' do
    it 'delegates to gateway_auth_api' do
      expect(gateway_auth_api).to receive(:get_config).with('cfg-1')
      client.get_gateway_auth_config('cfg-1')
    end
  end

  describe '#list_gateway_auth_configs' do
    it 'delegates to gateway_auth_api' do
      expect(gateway_auth_api).to receive(:list_configs).and_return([])
      client.list_gateway_auth_configs
    end
  end

  describe '#update_gateway_auth_config' do
    it 'delegates to gateway_auth_api' do
      config = double('config')
      expect(gateway_auth_api).to receive(:update_config).with('cfg-1', config)
      client.update_gateway_auth_config('cfg-1', config)
    end
  end

  describe '#delete_gateway_auth_config' do
    it 'delegates to gateway_auth_api' do
      expect(gateway_auth_api).to receive(:delete_config).with('cfg-1')
      client.delete_gateway_auth_config('cfg-1')
    end
  end
end

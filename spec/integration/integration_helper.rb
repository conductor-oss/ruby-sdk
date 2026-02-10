# frozen_string_literal: true

require 'bundler/setup'
require 'conductor'
require 'logger'

# Integration test helper for Conductor OSS and Orkes
# Tests run against a real Conductor server.
#
# Environment variables:
#   CONDUCTOR_SERVER_URL - Server URL (default: http://localhost:7001/api)
#   CONDUCTOR_AUTH_KEY   - Auth key (for Orkes, not needed for OSS)
#   CONDUCTOR_AUTH_SECRET - Auth secret (for Orkes, not needed for OSS)
#   CONDUCTOR_INTEGRATION - Set to 'true' to enable integration tests
#
# Usage:
#   CONDUCTOR_INTEGRATION=true bundle exec rspec spec/integration/

module IntegrationHelper
  CONDUCTOR_SERVER_URL = ENV.fetch('CONDUCTOR_SERVER_URL', 'http://localhost:7001/api')

  # Unique prefix for test resources to avoid collisions
  TEST_PREFIX = "ruby_sdk_test_#{Time.now.to_i}_#{rand(10_000)}".freeze

  def self.configuration
    @configuration ||= begin
      config = Conductor::Configuration.new(
        server_api_url: CONDUCTOR_SERVER_URL
      )

      # Configure auth if credentials are provided
      key_id = ENV.fetch('CONDUCTOR_AUTH_KEY', nil)
      key_secret = ENV.fetch('CONDUCTOR_AUTH_SECRET', nil)
      if key_id && key_secret
        config.authentication_settings = Conductor::Configuration::AuthenticationSettings.new(
          key_id: key_id,
          key_secret: key_secret
        )
      end

      config
    end
  end

  def self.metadata_client
    @metadata_client ||= Conductor::Client::MetadataClient.new(configuration)
  end

  def self.workflow_client
    @workflow_client ||= Conductor::Client::WorkflowClient.new(configuration)
  end

  def self.task_client
    @task_client ||= Conductor::Client::TaskClient.new(configuration)
  end

  # Test if the Conductor server is reachable
  def self.server_available?
    require 'net/http'
    uri = URI.parse("#{CONDUCTOR_SERVER_URL.sub(%r{/api$}, '')}/health")
    response = Net::HTTP.get_response(uri)
    response.code == '200'
  rescue StandardError
    false
  end

  # Generate a unique test name to prevent collisions
  def self.test_name(base_name)
    "#{TEST_PREFIX}_#{base_name}"
  end

  # Cleanup helper: silently delete a task definition
  def self.cleanup_task_def(name)
    metadata_client.unregister_task_def(name)
  rescue StandardError
    # Ignore errors during cleanup
  end

  # Cleanup helper: silently delete a workflow definition
  def self.cleanup_workflow_def(name, version: 1)
    metadata_client.unregister_workflow_def(name, version: version)
  rescue StandardError
    # Ignore errors during cleanup
  end

  # Cleanup helper: terminate and delete a workflow
  def self.cleanup_workflow(workflow_id)
    workflow_client.terminate_workflow(workflow_id, reason: 'test cleanup')
  rescue StandardError
    # Ignore errors during cleanup
  end

  # Wait for a workflow to reach a terminal state
  # @param workflow_id [String] Workflow ID
  # @param timeout [Integer] Timeout in seconds (default: 30)
  # @param poll_interval [Float] Poll interval in seconds (default: 0.5)
  # @return [Conductor::Http::Models::Workflow] Final workflow state
  def self.wait_for_workflow(workflow_id, timeout: 30, poll_interval: 0.5)
    deadline = Time.now + timeout
    loop do
      wf = workflow_client.get_workflow(workflow_id)
      return wf if wf.terminal? || Time.now >= deadline

      sleep(poll_interval)
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_integration_status'
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Tag all integration specs
  config.define_derived_metadata(file_path: %r{spec/integration}) do |metadata|
    metadata[:integration] = true
  end

  # Skip integration tests unless explicitly enabled
  config.before(:each, :integration) do
    skip 'Integration tests disabled. Set CONDUCTOR_INTEGRATION=true to enable.' unless ENV['CONDUCTOR_INTEGRATION'] == 'true'

    skip "Conductor server not available at #{IntegrationHelper::CONDUCTOR_SERVER_URL}" unless IntegrationHelper.server_available?
  end

  # Run in defined order for integration tests
  config.order = :defined
end

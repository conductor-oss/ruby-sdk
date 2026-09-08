# frozen_string_literal: true

# Helper for the agents runtime specs (spec/agents). These run the real SDK against a
# server: by default a WireMock replay of a scenario recorded from conductor-oss
# (github.com/conductor-oss/conductor-mocks), so no Conductor server and no LLM key is
# needed.
#
# Tag an example group with `mocks: 'agent/tool_happy_path'`. The helper points the SDK at
# the replay server and, after each example, asserts that WireMock saw no unmatched request
# (an unmatched request means the SDK sent something the real server never received).
#
# Environment:
#   CONDUCTOR_AGENTS_REPLAY_URL  base URL of a running WireMock serving the scenario
#                                (e.g. http://localhost:8080). When unset and Docker is
#                                available, one is started from CONDUCTOR_MOCKS_DIR.
#   CONDUCTOR_MOCKS_DIR          checkout of conductor-mocks (default ../conductor-mocks)
#
# Usage:
#   CONDUCTOR_AGENTS_REPLAY_URL=http://localhost:8080 bundle exec rspec spec/agents
require 'bundler/setup'
require 'json'
require 'net/http'
require 'uri'
require 'conductor/agents'

module AgentsReplay
  DEFAULT_MOCKS_DIR = File.expand_path('../../../conductor-mocks', __dir__)
  WIREMOCK_IMAGE = 'wiremock/wiremock:3x'

  class << self
    attr_reader :base_url

    # Ensure a replay server for +scenario+ is reachable; returns false (with a reason) when it cannot be.
    def ensure_server(scenario)
      return [true, nil] if @base_url && @scenario == scenario

      if ENV['CONDUCTOR_AGENTS_REPLAY_URL']
        @base_url = ENV['CONDUCTOR_AGENTS_REPLAY_URL'].sub(%r{/+$}, '')
        @scenario = scenario
        return healthy? ? [true, nil] : [false, "WireMock at #{@base_url} is not answering"]
      end

      start_container(scenario)
    end

    def reset_scenarios
      admin_post('/__admin/scenarios/reset')
      admin_delete('/__admin/requests')
    end

    # @return [Array<Hash>] requests WireMock could not match
    def unmatched_requests
      body = admin_get('/__admin/requests/unmatched')
      JSON.parse(body).fetch('requests', [])
    rescue StandardError
      []
    end

    def server_api_url
      "#{@base_url}/api"
    end

    def stop
      return unless @container

      system('docker', 'rm', '-f', @container, out: File::NULL, err: File::NULL)
      @container = nil
    end

    private

    def start_container(scenario)
      dir = File.join(ENV.fetch('CONDUCTOR_MOCKS_DIR', DEFAULT_MOCKS_DIR), 'mocks', scenario)
      return [false, "scenario directory not found: #{dir}"] unless File.directory?(dir)
      return [false, 'docker is not available and CONDUCTOR_AGENTS_REPLAY_URL is unset'] unless system('docker', 'version', out: File::NULL, err: File::NULL)

      stop
      @container = "ruby-sdk-replay-#{Process.pid}"
      ok = system('docker', 'run', '-d', '--name', @container, '-p', '8080:8080', '-v', "#{dir}:/home/wiremock:z",
                  WIREMOCK_IMAGE, out: File::NULL, err: File::NULL)
      return [false, 'could not start the WireMock container'] unless ok

      @base_url = 'http://localhost:8080'
      @scenario = scenario
      30.times do
        return [true, nil] if healthy?

        sleep 1
      end
      [false, 'WireMock container did not become healthy']
    end

    def healthy?
      admin_get('/__admin/mappings')
      true
    rescue StandardError
      false
    end

    def admin_get(path)
      response = Net::HTTP.get_response(URI.parse("#{@base_url}#{path}"))
      raise "HTTP #{response.code}" unless response.code.to_i == 200

      response.body
    end

    def admin_post(path)
      uri = URI.parse("#{@base_url}#{path}")
      Net::HTTP.post(uri, '')
    end

    def admin_delete(path)
      uri = URI.parse("#{@base_url}#{path}")
      Net::HTTP.start(uri.host, uri.port) { |http| http.delete(uri.path) }
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_agents_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :defined

  config.before(:each, :mocks) do |example|
    ok, reason = AgentsReplay.ensure_server(example.metadata[:mocks])
    skip "replay server unavailable: #{reason}" unless ok

    AgentsReplay.reset_scenarios
    Conductor::Agents.configure(
      configuration: Conductor::Configuration.new(server_api_url: AgentsReplay.server_api_url),
      agent_config: Conductor::Agents::AgentConfig.new(worker_poll_interval_ms: 100),
      logger: Logger.new(ENV['CONDUCTOR_AGENTS_DEBUG'] ? $stdout : nil)
    )
  end

  config.after(:each, :mocks) do
    Conductor::Agents.shutdown
    unmatched = AgentsReplay.unmatched_requests
    expect(unmatched.map { |r| "#{r['method']} #{r['url']}" }).to eq([]), 'the SDK sent requests the recorded server never saw'
  end

  config.after(:suite) { AgentsReplay.stop }
end

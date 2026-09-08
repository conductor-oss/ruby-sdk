# frozen_string_literal: true

module Conductor
  module Agents
    # Runtime knobs, read from CONDUCTOR_AGENT_* environment variables (same names and
    # defaults as the Python SDK's AgentConfig).
    class AgentConfig
      TRUE_VALUES = %w[true 1 yes on].freeze
      FALSE_VALUES = %w[false 0 no off].freeze

      attr_accessor :worker_poll_interval_ms, :worker_thread_count, :auto_register_integrations,
                    :streaming_enabled, :status_poll_interval_seconds, :system_worker_thread_count

      def initialize(worker_poll_interval_ms: 100, worker_thread_count: 1, auto_register_integrations: false,
                     streaming_enabled: true, status_poll_interval_seconds: 0.5, system_worker_thread_count: 10)
        @worker_poll_interval_ms = worker_poll_interval_ms
        @worker_thread_count = worker_thread_count
        @auto_register_integrations = auto_register_integrations
        @streaming_enabled = streaming_enabled
        @status_poll_interval_seconds = status_poll_interval_seconds
        @system_worker_thread_count = system_worker_thread_count
      end

      # @param env [Hash] defaults to ENV
      def self.from_env(env = ENV)
        new(
          worker_poll_interval_ms: int(env, 'CONDUCTOR_AGENT_WORKER_POLL_INTERVAL', 100),
          worker_thread_count: int(env, 'CONDUCTOR_AGENT_WORKER_THREADS', 1),
          auto_register_integrations: bool(env, 'CONDUCTOR_AGENT_INTEGRATIONS_AUTO_REGISTER', false),
          streaming_enabled: bool(env, 'CONDUCTOR_AGENT_STREAMING_ENABLED', true)
        )
      end

      def self.int(env, key, default)
        raw = env[key].to_s.strip
        raw.empty? ? default : Integer(raw, 10)
      rescue ArgumentError
        default
      end

      def self.bool(env, key, default)
        raw = env[key].to_s.strip.downcase
        return default if raw.empty?
        return true if TRUE_VALUES.include?(raw)
        return false if FALSE_VALUES.include?(raw)

        default
      end
      private_class_method :int, :bool
    end
  end
end

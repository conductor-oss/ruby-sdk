# frozen_string_literal: true

require_relative 'legacy_metrics_collector'
require_relative 'canonical_metrics_collector'

module Conductor
  module Worker
    module Telemetry
      # MetricsCollector - Factory for creating the appropriate metrics
      # collector based on environment configuration.
      #
      # Currently checks WORKER_CANONICAL_METRICS (default false). When truthy,
      # returns a CanonicalMetricsCollector; otherwise a LegacyMetricsCollector.
      #
      # In a future release, when canonical metrics become the default,
      # WORKER_LEGACY_METRICS will be checked to allow opting back in to the
      # legacy implementation.
      module MetricsCollector
        # Create a metrics collector instance gated by environment configuration.
        #
        # @param backend [Symbol, Object] Backend type (:null, :prometheus) or custom backend
        # @param subscribe_global_http [Boolean] Auto-subscribe to HTTP events (canonical only)
        # @return [LegacyMetricsCollector, CanonicalMetricsCollector]
        def self.create(backend: :null, subscribe_global_http: true)
          if canonical_metrics_enabled?
            CanonicalMetricsCollector.new(backend: backend, subscribe_global_http: subscribe_global_http)
          else
            LegacyMetricsCollector.new(backend: backend)
          end
        end

        # @return [Boolean] true when the canonical metric set is selected
        def self.canonical_metrics_enabled?
          %w[true 1 yes].include?(ENV.fetch('WORKER_CANONICAL_METRICS', 'false').downcase.strip)
        end
      end

      # NullBackend - No-op backend for metrics
      # Used when metrics are disabled or not configured
      class NullBackend
        def increment(name, labels: {})
          # No-op
        end

        def observe(name, value, labels: {})
          # No-op
        end

        def set(name, value, labels: {})
          # No-op
        end
      end
    end
  end
end

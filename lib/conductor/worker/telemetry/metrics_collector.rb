# frozen_string_literal: true

require 'logger'
require_relative '../events/listeners'
require_relative '../events/global_dispatcher'

module Conductor
  module Worker
    module Telemetry
      # MetricsCollector - Canonical SDK worker metrics from the
      # harmonization spec (sdk-metrics-harmonization.md).
      #
      # Uses camelCase domain labels (taskType, workflowType) and includes
      # status labels on time histograms.
      class MetricsCollector
        include Events::TaskRunnerEventsListener
        include Events::WorkflowEventsListener
        include Events::HttpEventsListener

        STATUS_SUCCESS = 'SUCCESS'
        STATUS_FAILURE = 'FAILURE'

        # @param backend [Symbol, Object] :null, :prometheus, or a custom backend
        # @param subscribe_global_http [Boolean] Auto-subscribe to GlobalDispatcher
        #   for HttpApiRequest events from the HTTP layer (default true).
        # @param measure_payload_size [Boolean] Record workflow_input_size_bytes
        #   (requires JSON serialization; default true). Set false to skip
        #   serialization overhead for large payloads.
        # @param logger [Logger, nil] Optional logger for diagnostic output in rescue blocks
        # @return [MetricsCollector]
        def self.create(backend: :null, subscribe_global_http: true, measure_payload_size: true, logger: nil)
          new(backend: backend, subscribe_global_http: subscribe_global_http,
              measure_payload_size: measure_payload_size, logger: logger)
        end

        def initialize(backend: :null, subscribe_global_http: true, measure_payload_size: true, logger: nil)
          @backend = load_backend(backend)
          @logger = logger || Logger.new(File::NULL)
          @measure_payload_size = measure_payload_size
          @http_listener = nil
          subscribe_to_global_http_events if subscribe_global_http
        end

        attr_reader :backend, :measure_payload_size

        def stop
          return unless @http_listener

          Events::GlobalDispatcher.instance.unregister(Events::HttpApiRequest, @http_listener)
          @http_listener = nil
        rescue StandardError => e
          @logger.debug { "Telemetry error (non-fatal): #{e.class}: #{e.message}" }
        end

        # --- Task Runner Event Handlers ---

        def on_poll_started(event)
          @backend.increment('task_poll_total', labels: { taskType: event.task_type })
        end

        def on_poll_completed(event)
          observe_time('task_poll_time_seconds', event.duration_ms,
                       { taskType: event.task_type, status: STATUS_SUCCESS })
        end

        def on_poll_failure(event)
          @backend.increment('task_poll_error_total',
                             labels: { taskType: event.task_type, exception: event.cause.class.name })
          observe_time('task_poll_time_seconds', event.duration_ms,
                       { taskType: event.task_type, status: STATUS_FAILURE })
        end

        def on_task_execution_started(event)
          @backend.increment('task_execution_started_total', labels: { taskType: event.task_type })
        end

        def on_task_execution_completed(event)
          observe_time('task_execute_time_seconds', event.duration_ms,
                       { taskType: event.task_type, status: STATUS_SUCCESS })

          return unless event.output_size_bytes

          @backend.observe('task_result_size_bytes', event.output_size_bytes,
                           labels: { taskType: event.task_type })
        end

        def on_task_execution_failure(event)
          @backend.increment('task_execute_error_total',
                             labels: { taskType: event.task_type, exception: event.cause.class.name })
          observe_time('task_execute_time_seconds', event.duration_ms,
                       { taskType: event.task_type, status: STATUS_FAILURE })
        end

        def on_task_update_completed(event)
          observe_time('task_update_time_seconds', event.duration_ms,
                       { taskType: event.task_type, status: STATUS_SUCCESS })
        end

        def on_task_update_failure(event)
          @backend.increment('task_update_error_total',
                             labels: { taskType: event.task_type, exception: event.cause.class.name })

          return unless event.respond_to?(:duration_ms) && event.duration_ms

          observe_time('task_update_time_seconds', event.duration_ms,
                       { taskType: event.task_type, status: STATUS_FAILURE })
        end

        def on_task_paused(event)
          @backend.increment('task_paused_total', labels: { taskType: event.task_type })
        end

        def on_thread_uncaught_exception(event)
          @backend.increment('thread_uncaught_exceptions_total',
                             labels: { exception: event.cause.class.name })
        end

        def on_active_workers_changed(event)
          @backend.set('active_workers', event.count, labels: { taskType: event.task_type })
        end

        # --- Workflow Event Handlers ---

        def on_workflow_start_error(event)
          @backend.increment('workflow_start_error_total',
                             labels: { workflowType: event.workflow_type,
                                       exception: event.cause.class.name })
        end

        def on_workflow_input_size(event)
          return unless @measure_payload_size

          @backend.observe('workflow_input_size_bytes', event.size_bytes,
                           labels: { workflowType: event.workflow_type,
                                     version: (event.version || '').to_s })
        end

        # --- HTTP Event Handlers ---

        def on_http_api_request(event)
          observe_time('http_api_client_request_seconds', event.duration_ms,
                       { method: event.method, uri: event.uri, status: event.status })
        end

        private

        def observe_time(name, duration_ms, labels)
          @backend.observe(name, duration_ms / 1000.0, labels: labels)
        end

        def subscribe_to_global_http_events
          @http_listener = ->(event) { on_http_api_request(event) }
          Events::GlobalDispatcher.instance.register(Events::HttpApiRequest, @http_listener)
        rescue StandardError => e
          @logger.debug { "Telemetry error (non-fatal): #{e.class}: #{e.message}" }
        end

        def load_backend(backend)
          case backend
          when :null, nil
            NullBackend.new
          when :prometheus
            load_prometheus_backend
          else
            backend
          end
        end

        def load_prometheus_backend
          require_relative 'prometheus_backend'
          PrometheusBackend.new
        rescue LoadError
          raise ConfigurationError,
                "The 'prometheus-client' gem is required for Prometheus metrics. " \
                "Add `gem 'prometheus-client'` to your Gemfile."
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

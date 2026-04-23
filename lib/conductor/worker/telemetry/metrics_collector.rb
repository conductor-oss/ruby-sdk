# frozen_string_literal: true

require_relative '../events/listeners'
require_relative '../events/global_dispatcher'
require_relative '../events/listener_registry'

module Conductor
  module Worker
    module Telemetry
      # MetricsCollector - Collects canonical SDK worker metrics from worker,
      # workflow, and HTTP events.
      #
      # Implements the TaskRunnerEventsListener, WorkflowEventsListener, and
      # HttpEventsListener protocols so the ListenerRegistry can auto-wire
      # all three families of events via duck-typing.
      #
      # Canonical metric names and labels follow
      # https://github.com/orkes-io/certification-cloud-util/blob/main/sdk-metrics-harmonization.md
      # Label-wise, pre-existing worker-level metrics carry both `taskType` (camelCase,
      # canonical) and `task_type` (snake_case, Ruby-legacy) with identical values.
      # Metrics that are new to Ruby use canonical-only labels (§3.4 label strategy).
      class MetricsCollector
        include Events::TaskRunnerEventsListener
        include Events::WorkflowEventsListener
        include Events::HttpEventsListener

        STATUS_SUCCESS = 'SUCCESS'
        STATUS_FAILURE = 'FAILURE'

        # Initialize metrics collector
        # @param backend [Symbol, Object] Backend type (:null, :prometheus) or custom backend
        # @param subscribe_global_http [Boolean] When true, auto-subscribe this collector to the
        #   process-wide GlobalDispatcher so HttpApiRequest events emitted by the HTTP layer flow
        #   through. Enabled by default. Pass false if you are already wiring a local dispatcher.
        def initialize(backend: :null, subscribe_global_http: true)
          @backend = load_backend(backend)
          subscribe_to_global_http_events if subscribe_global_http
        end

        # @return [Object] The metrics backend
        attr_reader :backend

        # --- Task Runner Event Handlers ---

        def on_poll_started(event)
          @backend.increment('task_poll_total', labels: task_labels(event.task_type))
        end

        def on_poll_completed(event)
          observe_time('task_poll_time_seconds', event.duration_ms,
                       task_labels(event.task_type).merge(status: STATUS_SUCCESS))
        end

        def on_poll_failure(event)
          exception = event.cause.class.name
          # Dual-emit the old `error` label + the canonical `exception` label on the same series
          # so existing dashboards (if any) continue to work.
          @backend.increment('task_poll_error_total',
                             labels: task_labels(event.task_type).merge(
                               exception: exception,
                               error: exception
                             ))
          observe_time('task_poll_time_seconds', event.duration_ms,
                       task_labels(event.task_type).merge(status: STATUS_FAILURE))
        end

        def on_task_execution_started(event)
          @backend.increment('task_execution_started_total', labels: task_labels(event.task_type, legacy: false))
        end

        def on_task_execution_completed(event)
          observe_time('task_execute_time_seconds', event.duration_ms,
                       task_labels(event.task_type).merge(status: STATUS_SUCCESS))

          return unless event.output_size_bytes

          # Canonical shape: last-value Gauge (new to Ruby — canonical-only labels).
          @backend.set('task_result_size_bytes', event.output_size_bytes,
                       labels: task_labels(event.task_type, legacy: false))
          # Legacy Ruby-specific Histogram retained under its renamed name for Phase 1.
          @backend.observe('task_result_size_bytes_histogram', event.output_size_bytes,
                           labels: { task_type: event.task_type })
        end

        def on_task_execution_failure(event)
          @backend.increment('task_execute_error_total',
                             labels: task_labels(event.task_type).merge(
                               exception: event.cause.class.name,
                               retryable: event.is_retryable.to_s
                             ))
          observe_time('task_execute_time_seconds', event.duration_ms,
                       task_labels(event.task_type).merge(status: STATUS_FAILURE))
        end

        def on_task_update_completed(event)
          observe_time('task_update_time_seconds', event.duration_ms,
                       task_labels(event.task_type, legacy: false).merge(status: STATUS_SUCCESS))
        end

        def on_task_update_failure(event)
          # Legacy name, kept emitting during Phase 1.
          @backend.increment('task_update_failed_total',
                             labels: { task_type: event.task_type })
          # Canonical name.
          @backend.increment('task_update_error_total',
                             labels: task_labels(event.task_type).merge(
                               exception: event.cause.class.name
                             ))
          return unless event.respond_to?(:duration_ms) && event.duration_ms

          observe_time('task_update_time_seconds', event.duration_ms,
                       task_labels(event.task_type, legacy: false).merge(status: STATUS_FAILURE))
        end

        def on_task_paused(event)
          @backend.increment('task_paused_total', labels: task_labels(event.task_type, legacy: false))
        end

        def on_thread_uncaught_exception(event)
          @backend.increment('thread_uncaught_exceptions_total',
                             labels: { exception: event.cause.class.name })
        end

        def on_active_workers_changed(event)
          @backend.set('active_workers', event.count, labels: task_labels(event.task_type))
        end

        # --- Workflow Event Handlers ---

        def on_workflow_start_error(event)
          @backend.increment('workflow_start_error_total',
                             labels: {
                               workflowType: event.workflow_type,
                               exception: event.cause.class.name
                             })
        end

        def on_workflow_input_size(event)
          @backend.set('workflow_input_size_bytes', event.size_bytes,
                       labels: {
                         workflowType: event.workflow_type,
                         version: (event.version || '').to_s
                       })
        end

        # --- HTTP Event Handlers ---

        def on_http_api_request(event)
          observe_time('http_api_client_request_seconds', event.duration_ms,
                       { method: event.method, uri: event.uri, status: event.status })
        end

        private

        # Build the label hash for worker metrics.
        # @param task_type [String]
        # @param legacy [Boolean] When true (default), emits both the canonical
        #   `taskType` and the Ruby-legacy `task_type` for backward-compat.
        #   Pass false for metrics that are new to Ruby (§3.4 canonical-only).
        # @return [Hash]
        def task_labels(task_type, legacy: true)
          labels = { taskType: task_type }
          labels[:task_type] = task_type if legacy
          labels
        end

        # Observe a time measurement in seconds. Accepts milliseconds (the unit used
        # on every event) and divides here once.
        def observe_time(name, duration_ms, labels)
          @backend.observe(name, duration_ms / 1000.0, labels: labels)
        end

        # Subscribe to the process-wide HTTP event dispatcher so HttpApiRequest
        # events fired from RestClient flow through regardless of which ApiClient
        # instance generated them.
        def subscribe_to_global_http_events
          Events::ListenerRegistry.register_task_runner_listener(
            self, Events::GlobalDispatcher.instance
          )
        rescue StandardError
          # Telemetry subscription must never break SDK bootstrap
        end

        # Load a metrics backend
        # @param backend [Symbol, Object] Backend type or instance
        # @return [Object] Backend instance
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

        # Load Prometheus backend (lazy loading)
        # @return [PrometheusBackend]
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

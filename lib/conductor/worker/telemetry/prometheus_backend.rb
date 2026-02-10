# frozen_string_literal: true

module Conductor
  module Worker
    module Telemetry
      # PrometheusBackend - Prometheus metrics backend
      # Uses the prometheus-client gem for metric collection
      #
      # Metrics exposed:
      # - task_poll_total (Counter)
      # - task_poll_time_seconds (Histogram)
      # - task_poll_error_total (Counter)
      # - task_execute_time_seconds (Histogram)
      # - task_execute_error_total (Counter)
      # - task_result_size_bytes (Histogram)
      # - task_update_failed_total (Counter)
      #
      # @example
      #   collector = MetricsCollector.new(backend: :prometheus)
      #   # Metrics available at default prometheus registry
      class PrometheusBackend
        # Default histogram buckets for time measurements (in seconds)
        TIME_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze

        # Default histogram buckets for size measurements (in bytes)
        SIZE_BUCKETS = [100, 1000, 10_000, 100_000, 1_000_000, 10_000_000].freeze

        def initialize(registry: nil)
          load_prometheus_client
          @registry = registry || Prometheus::Client.registry
          setup_metrics
        end

        # Increment a counter
        # @param name [String] Metric name
        # @param labels [Hash] Metric labels
        # @param value [Integer] Value to increment by (default: 1)
        def increment(name, labels: {}, value: 1)
          metric = get_or_create_counter(name)
          metric.increment(labels: normalize_labels(labels), by: value)
        end

        # Observe a value in a histogram
        # @param name [String] Metric name
        # @param value [Numeric] Value to observe
        # @param labels [Hash] Metric labels
        def observe(name, value, labels: {})
          metric = get_or_create_histogram(name)
          metric.observe(value, labels: normalize_labels(labels))
        end

        # Set a gauge value
        # @param name [String] Metric name
        # @param value [Numeric] Value to set
        # @param labels [Hash] Metric labels
        def set(name, value, labels: {})
          metric = get_or_create_gauge(name)
          metric.set(value, labels: normalize_labels(labels))
        end

        # Get the prometheus registry
        # @return [Prometheus::Client::Registry]
        attr_reader :registry

        private

        # Load prometheus-client gem
        def load_prometheus_client
          require 'prometheus/client'
        rescue LoadError
          raise ConfigurationError,
                "The 'prometheus-client' gem is required for Prometheus metrics. " \
                "Add `gem 'prometheus-client'` to your Gemfile."
        end

        # Setup predefined metrics
        def setup_metrics
          # Counters
          @counters = {}
          @histograms = {}
          @gauges = {}

          # Pre-register common metrics
          register_counter('task_poll_total', 'Total number of task polls')
          register_counter('task_poll_error_total', 'Total number of poll errors')
          register_counter('task_execute_error_total', 'Total number of execution errors')
          register_counter('task_update_failed_total', 'Total number of failed task updates (CRITICAL)')

          register_histogram('task_poll_time_seconds', 'Task poll duration in seconds', TIME_BUCKETS)
          register_histogram('task_execute_time_seconds', 'Task execution duration in seconds', TIME_BUCKETS)
          register_histogram('task_result_size_bytes', 'Task result size in bytes', SIZE_BUCKETS)
        end

        # Register a counter metric
        # @param name [String] Metric name
        # @param docstring [String] Metric description
        def register_counter(name, docstring)
          metric_name = name.to_sym
          return if @registry.exist?(metric_name)

          counter = Prometheus::Client::Counter.new(
            metric_name,
            docstring: docstring,
            labels: %i[task_type error exception retryable]
          )
          @registry.register(counter)
          @counters[name] = counter
        end

        # Register a histogram metric
        # @param name [String] Metric name
        # @param docstring [String] Metric description
        # @param buckets [Array<Numeric>] Histogram buckets
        def register_histogram(name, docstring, buckets)
          metric_name = name.to_sym
          return if @registry.exist?(metric_name)

          histogram = Prometheus::Client::Histogram.new(
            metric_name,
            docstring: docstring,
            labels: [:task_type],
            buckets: buckets
          )
          @registry.register(histogram)
          @histograms[name] = histogram
        end

        # Register a gauge metric
        # @param name [String] Metric name
        # @param docstring [String] Metric description
        def register_gauge(name, docstring)
          metric_name = name.to_sym
          return if @registry.exist?(metric_name)

          gauge = Prometheus::Client::Gauge.new(
            metric_name,
            docstring: docstring,
            labels: [:task_type]
          )
          @registry.register(gauge)
          @gauges[name] = gauge
        end

        # Get or create a counter metric
        # @param name [String] Metric name
        # @return [Prometheus::Client::Counter]
        def get_or_create_counter(name)
          @counters[name] ||= begin
            metric_name = name.to_sym
            if @registry.exist?(metric_name)
              @registry.get(metric_name)
            else
              counter = Prometheus::Client::Counter.new(
                metric_name,
                docstring: "Counter for #{name}",
                labels: %i[task_type error exception retryable]
              )
              @registry.register(counter)
              counter
            end
          end
        end

        # Get or create a histogram metric
        # @param name [String] Metric name
        # @return [Prometheus::Client::Histogram]
        def get_or_create_histogram(name)
          @histograms[name] ||= begin
            metric_name = name.to_sym
            if @registry.exist?(metric_name)
              @registry.get(metric_name)
            else
              buckets = name.include?('bytes') ? SIZE_BUCKETS : TIME_BUCKETS
              histogram = Prometheus::Client::Histogram.new(
                metric_name,
                docstring: "Histogram for #{name}",
                labels: [:task_type],
                buckets: buckets
              )
              @registry.register(histogram)
              histogram
            end
          end
        end

        # Get or create a gauge metric
        # @param name [String] Metric name
        # @return [Prometheus::Client::Gauge]
        def get_or_create_gauge(name)
          @gauges[name] ||= begin
            metric_name = name.to_sym
            if @registry.exist?(metric_name)
              @registry.get(metric_name)
            else
              gauge = Prometheus::Client::Gauge.new(
                metric_name,
                docstring: "Gauge for #{name}",
                labels: [:task_type]
              )
              @registry.register(gauge)
              gauge
            end
          end
        end

        # Normalize labels - convert keys to symbols and filter out nil/empty values
        # @param labels [Hash] Input labels
        # @return [Hash] Normalized labels
        def normalize_labels(labels)
          result = {}
          labels.each do |key, value|
            next if value.nil?

            sym_key = key.to_sym
            result[sym_key] = value.to_s
          end

          # Ensure required labels have default values
          result[:task_type] ||= 'unknown'
          result
        end
      end

      # MetricsServer - HTTP server for exposing Prometheus metrics
      # Serves metrics at /metrics endpoint
      class MetricsServer
        DEFAULT_PORT = 9090

        # Initialize metrics server
        # @param port [Integer] Port to listen on (default: 9090)
        # @param registry [Prometheus::Client::Registry] Prometheus registry
        def initialize(port: DEFAULT_PORT, registry: nil)
          require 'prometheus/client'
          require 'prometheus/client/formats/text'
          require 'webrick'

          @port = port
          @registry = registry || Prometheus::Client.registry
          @server = nil
        end

        # Start the metrics server in a background thread
        # @return [Thread] Server thread
        def start
          @server = WEBrick::HTTPServer.new(
            Port: @port,
            Logger: WEBrick::Log.new('/dev/null'),
            AccessLog: []
          )

          @server.mount_proc '/metrics' do |_req, res|
            res.content_type = 'text/plain; version=0.0.4'
            res.body = Prometheus::Client::Formats::Text.marshal(@registry)
          end

          @server.mount_proc '/health' do |_req, res|
            res.content_type = 'application/json'
            res.body = '{"status":"healthy"}'
          end

          @thread = Thread.new { @server.start }
          @thread.name = 'prometheus-metrics-server'
          @thread
        end

        # Stop the metrics server
        def stop
          @server&.shutdown
          @thread&.join(5)
        end

        # @return [Integer] Server port
        attr_reader :port
      end
    end
  end
end

# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'logger'
require_relative '../errors'

module Conductor
  module Agents
    # Server-sent events from GET /api/agent/stream/{executionId}.
    #
    # Uses a plain Net::HTTP streaming request (the shared Faraday RestClient buffers
    # bodies, retries, and has a 120 s total timeout, none of which suit a long-lived
    # stream). Auth headers come from the ApiClient so token refresh stays in one place.
    #
    # Wire format (see AgentStreamRegistry on the server): ":connected" first, then
    # "id:<n>\nevent:<type>\ndata:<json>\n\n" frames, a ":heartbeat" comment every 15 s, the
    # stream closes after "done" or "error". Last-Event-ID (a bare integer) resumes; without
    # it the server replays from the start, so connecting after start loses nothing.
    class SseClient
      HEARTBEAT_ONLY_TIMEOUT = 15
      RECONNECT_DELAY = 1
      TERMINAL_EVENTS = %w[done error].freeze
      READ_TIMEOUT = 60
      OPEN_TIMEOUT = 5

      # Incremental parser for the SSE wire format
      class Parser
        def initialize
          @buffer = +''
          @event = nil
          @id = nil
          @data = []
        end

        # Feed a chunk; yields each complete event as { 'event', 'id', 'data' } or { 'heartbeat' => true }
        def feed(chunk, &block)
          @buffer << chunk
          while (idx = @buffer.index("\n"))
            line = @buffer.slice!(0..idx).chomp
            process_line(line, &block)
          end
        end

        private

        def process_line(line, &block)
          if line.start_with?(':')
            yield({ 'heartbeat' => true })
          elsif line.empty?
            flush(&block)
          elsif (m = line.match(/\A(\w+):\s?(.*)\z/m))
            field = m[1]
            value = m[2]
            case field
            when 'event' then @event = value
            when 'id' then @id = value
            when 'data' then @data << value
            end
          end
        end

        def flush
          return if @data.empty? && @event.nil?

          raw = @data.join("\n")
          data = begin
            raw.empty? ? {} : JSON.parse(raw)
          rescue JSON::ParserError
            { 'content' => raw }
          end
          data = { 'content' => data } unless data.is_a?(Hash)
          id = @id.to_s =~ /\A\d+\z/ ? @id.to_i : @id
          yield({ 'event' => @event || data['type'], 'id' => id, 'data' => data })
        ensure
          @event = nil
          @id = nil
          @data = []
        end
      end

      # @param api_client [Http::ApiClient] supplies base URL, TLS settings and auth headers
      def initialize(api_client, logger: nil)
        @api_client = api_client
        @configuration = api_client.configuration
        @logger = logger || Logger.new($stdout, level: Logger::INFO)
      end

      # Yield every real event for +execution_id+ until done/error, reconnecting on drops.
      # @param last_event_id [Integer, nil] resume point
      # @raise [SseUnavailableError] when the first connection fails or only heartbeats arrive
      def each_event(execution_id, last_event_id: nil)
        return enum_for(:each_event, execution_id, last_event_id: last_event_id) unless block_given?

        first_connect = true
        got_real_event = false

        loop do
          begin
            finished = connect(execution_id, last_event_id) do |event|
              if event['heartbeat']
                next unless !got_real_event && Time.now - @connected_at > HEARTBEAT_ONLY_TIMEOUT

                raise SseUnavailableError, "SSE connected but only heartbeats arrived for #{HEARTBEAT_ONLY_TIMEOUT}s"
              end
              first_connect = false
              got_real_event = true
              last_event_id = event['id'] if event['id'].is_a?(Integer)
              yield event
              return if TERMINAL_EVENTS.include?(event['event'].to_s)
            end
            first_connect = false
            return if finished
          rescue SseUnavailableError
            raise
          rescue StandardError => e
            raise SseUnavailableError, "SSE unavailable: #{e.class}: #{e.message}" if first_connect

            @logger.warn("SSE connection lost (#{e.class}: #{e.message}), reconnecting in #{RECONNECT_DELAY}s")
          end
          sleep RECONNECT_DELAY
        end
      end

      private

      # Open one streaming request. Returns true when a terminal event was seen, false on EOF.
      def connect(execution_id, last_event_id)
        uri = URI.parse("#{@configuration.server_url}/agent/stream/#{execution_id}")
        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'text/event-stream'
        request['Cache-Control'] = 'no-cache'
        request['Last-Event-ID'] = last_event_id.to_s if last_event_id
        auth_headers.each { |k, v| request[k] = v }

        parser = Parser.new
        terminal = false
        Net::HTTP.start(uri.host, uri.port, **http_options(uri)) do |http|
          http.request(request) do |response|
            raise SseUnavailableError, "SSE endpoint returned HTTP #{response.code}" unless response.code.to_i == 200

            @connected_at = Time.now
            response.read_body do |chunk|
              parser.feed(chunk) do |event|
                yield event
                terminal = true if TERMINAL_EVENTS.include?(event['event'].to_s)
              end
              break if terminal
            end
          end
        end
        terminal
      end

      def auth_headers
        return {} unless @configuration.auth_configured?

        @api_client.get_authentication_headers || {}
      rescue StandardError => e
        @logger.warn("Could not attach auth headers to SSE request: #{e.message}")
        {}
      end

      def http_options(uri)
        opts = { use_ssl: uri.scheme == 'https', read_timeout: READ_TIMEOUT, open_timeout: OPEN_TIMEOUT }
        if opts[:use_ssl]
          opts[:verify_mode] = @configuration.verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
          opts[:ca_file] = @configuration.ssl_ca_cert if @configuration.ssl_ca_cert
        end
        opts
      end
    end
  end
end

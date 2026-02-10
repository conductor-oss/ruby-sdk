# frozen_string_literal: true

require 'faraday'
require 'faraday/net_http_persistent'
require 'faraday/retry'
require 'json'

module Conductor
  module Http
    # Faraday-based REST client with HTTP/2 support
    class RestClient
      attr_reader :connection

      def initialize(configuration = nil)
        @configuration = configuration
        @connection = build_connection
      end

      # Main request method
      def request(method, url, query: nil, headers: nil, body: nil)
        method = method.to_s.upcase
        raise ArgumentError, "Invalid HTTP method: #{method}" unless valid_method?(method)

        headers ||= {}
        headers['Content-Type'] ||= 'application/json' if %w[POST PUT PATCH DELETE OPTIONS].include?(method)

        response = @connection.run_request(method.downcase.to_sym, url, nil, headers) do |req|
          req.params = query if query
          req.body = serialize_body(body, headers['Content-Type']) if body
        end

        handle_response(response)
      rescue Faraday::TimeoutError => e
        raise ApiError.new("Request timeout: #{e.message}", status: 0, reason: 'Timeout')
      rescue Faraday::ConnectionFailed => e
        raise ApiError.new("Connection error: #{e.message}", status: 0, reason: 'ConnectionFailed')
      end

      # Convenience methods
      def get(url, query: nil, headers: nil)
        request('GET', url, query: query, headers: headers)
      end

      def post(url, body: nil, query: nil, headers: nil)
        request('POST', url, query: query, headers: headers, body: body)
      end

      def put(url, body: nil, query: nil, headers: nil)
        request('PUT', url, query: query, headers: headers, body: body)
      end

      def patch(url, body: nil, query: nil, headers: nil)
        request('PATCH', url, query: query, headers: headers, body: body)
      end

      def delete(url, body: nil, query: nil, headers: nil)
        request('DELETE', url, query: query, headers: headers, body: body)
      end

      def head(url, query: nil, headers: nil)
        request('HEAD', url, query: query, headers: headers)
      end

      def options(url, body: nil, query: nil, headers: nil)
        request('OPTIONS', url, query: query, headers: headers, body: body)
      end

      def close
        @connection&.close
      end

      private

      def build_connection
        Faraday.new do |conn|
          # HTTP/2 adapter with persistent connections
          conn.adapter :net_http_persistent do |http|
            http.idle_timeout = 30
          end

          # Retry middleware (3 retries with exponential backoff)
          conn.request :retry,
                       max: 3,
                       interval: 0.5,
                       backoff_factor: 2,
                       retry_statuses: [408, 429, 500, 502, 503, 504],
                       methods: %i[get post put patch delete]

          # Connection settings
          conn.options.timeout = 120      # 120s total timeout
          conn.options.open_timeout = 10  # 10s connection timeout

          # SSL settings from configuration
          if @configuration
            conn.ssl.verify = @configuration.verify_ssl
            conn.ssl.ca_file = @configuration.ssl_ca_cert if @configuration.ssl_ca_cert
            conn.ssl.client_cert = @configuration.cert_file if @configuration.cert_file
            conn.ssl.client_key = @configuration.key_file if @configuration.key_file
          end

          # Proxy settings
          conn.proxy = @configuration.proxy if @configuration&.proxy
        end
      end

      def valid_method?(method)
        %w[GET HEAD DELETE POST PUT PATCH OPTIONS].include?(method)
      end

      def serialize_body(body, content_type)
        return body if body.is_a?(String)

        if content_type&.include?('json')
          body.is_a?(Hash) || body.is_a?(Array) ? JSON.generate(body) : body.to_s
        else
          body
        end
      end

      def handle_response(response)
        # Check for auth errors first (401/403)
        if [401, 403].include?(response.status)
          raise AuthorizationError.new(
            "Authorization failed: #{response.status}",
            status: response.status,
            body: response.body,
            headers: response.headers.to_h
          )
        end

        # Check for other non-2xx responses
        unless (200..299).cover?(response.status)
          error_message = parse_error_message(response)
          raise ApiError.new(
            error_message,
            status: response.status,
            code: response.status,
            reason: response.reason_phrase,
            body: response.body,
            headers: response.headers.to_h
          )
        end

        # Return successful response
        RestResponse.new(response)
      end

      def parse_error_message(response)
        # Try to parse JSON error message
        data = begin
          JSON.parse(response.body)
        rescue StandardError
          nil
        end
        message = data&.dig('message') || response.reason_phrase || "HTTP #{response.status}"
        "(#{response.status}) #{message}"
      end
    end

    # Wrapper for Faraday response
    class RestResponse
      attr_reader :status, :reason, :body, :headers

      def initialize(faraday_response)
        @status = faraday_response.status
        @reason = faraday_response.reason_phrase
        @body = faraday_response.body
        @headers = faraday_response.headers.to_h
      end

      def json
        @json ||= JSON.parse(@body) if @body && !@body.empty?
      rescue JSON::ParserError
        nil
      end
    end
  end
end

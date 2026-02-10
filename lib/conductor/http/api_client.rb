# frozen_string_literal: true

require 'json'
require 'time'
require 'base64'
require 'uri'
require_relative '../configuration'
require_relative '../exceptions'
require_relative 'rest_client'
require_relative 'models/token'

module Conductor
  module Http
    # ApiClient handles HTTP communication and serialization/deserialization for Conductor API.
    # It manages authentication tokens with automatic refresh and exponential backoff on failures.
    class ApiClient
      PRIMITIVE_TYPES = [String, Integer, Float, TrueClass, FalseClass, NilClass].freeze
      NATIVE_TYPE_MAPPING = {
        'String' => String,
        'Integer' => Integer,
        'Float' => Float,
        'Boolean' => :boolean,
        'DateTime' => DateTime,
        'Date' => Date,
        'Time' => Time,
        'Object' => Object
      }.freeze

      attr_reader :configuration, :rest_client, :last_response
      attr_accessor :default_headers

      # Initialize ApiClient
      # @param [Configuration] configuration Configuration object
      # @param [Hash] default_headers Optional default headers
      def initialize(configuration: nil, default_headers: {})
        @configuration = configuration || Configuration.new
        @rest_client = RestClient.new(@configuration)
        @default_headers = get_default_headers.merge(default_headers)

        # Token refresh backoff tracking
        @token_refresh_failures = 0
        @last_token_refresh_attempt = 0
        @max_token_refresh_failures = 5

        # Mutex for thread-safe token refresh
        @token_refresh_mutex = Mutex.new

        # Initial token fetch
        refresh_auth_token
      end

      # Main API call method with automatic retry on auth failures
      # @param [String] resource_path The resource path
      # @param [String] method HTTP method (GET, POST, PUT, DELETE, PATCH)
      # @param [Hash] opts Optional parameters
      # @option opts [Hash] :path_params Path parameters
      # @option opts [Hash] :query_params Query parameters
      # @option opts [Hash] :header_params Header parameters
      # @option opts [Object] :body Request body
      # @option opts [String] :return_type Expected return type
      # @option opts [Boolean] :return_http_data_only Return only data (default: false)
      # @return [Array, Object] Response data (and status/headers if return_http_data_only is false)
      def call_api(resource_path, method, opts = {})
        call_api_with_retry(resource_path, method, opts)
      rescue AuthorizationError => e
        if e.token_expired? || e.invalid_token?
          token_status = e.token_expired? ? 'expired' : 'invalid'
          logger.info("Authentication token is #{token_status}, renewing token... (request: #{method} #{resource_path})")
          
          if force_refresh_auth_token
            logger.debug('Authentication token successfully renewed')
            # Retry the request once after successful token refresh
            return call_api_no_retry(resource_path, method, opts)
          else
            logger.error('Failed to renew authentication token. Please check your credentials.')
          end
        end
        raise
      end

      # Sanitize object for serialization to JSON
      # @param [Object] obj Object to sanitize
      # @return [Object] Sanitized object ready for JSON serialization
      def sanitize_for_serialization(obj)
        return nil if obj.nil?
        return obj if PRIMITIVE_TYPES.any? { |type| obj.is_a?(type) }

        case obj
        when Array
          obj.map { |item| sanitize_for_serialization(item) }
        when Hash
          obj.each_with_object({}) do |(key, val), hash|
            hash[key] = sanitize_for_serialization(val)
          end
        when DateTime, Date, Time
          obj.iso8601
        else
          # Handle model objects with ATTRIBUTE_MAP and SWAGGER_TYPES
          if obj.class.const_defined?(:ATTRIBUTE_MAP) && obj.class.const_defined?(:SWAGGER_TYPES)
            attr_map = obj.class.const_get(:ATTRIBUTE_MAP)
            swagger_types = obj.class.const_get(:SWAGGER_TYPES)
            
            swagger_types.each_with_object({}) do |(attr, _type), hash|
              value = obj.send(attr)
              next if value.nil?
              
              json_key = attr_map[attr]
              hash[json_key] = sanitize_for_serialization(value)
            end
          elsif obj.respond_to?(:to_h)
            sanitize_for_serialization(obj.to_h)
          else
            obj.to_s
          end
        end
      end

      # Deserialize HTTP response body into object
      # @param [RestResponse] response HTTP response
      # @param [String] return_type Expected return type (e.g., 'String', 'Array<Task>', 'Hash<String, Object>')
      # @return [Object] Deserialized object
      def deserialize(response, return_type)
        return nil if response.nil? || return_type.nil?
        body = response.body
        return nil if body.nil? || body.empty?

        # For String return type, return the raw body directly
        # (many Conductor APIs return plain text, e.g. workflow ID)
        if return_type == 'String'
          return body.to_s.strip.delete_prefix('"').delete_suffix('"')
        end

        # Parse response body as JSON for complex types
        data = response.json
        if data.nil?
          # JSON parsing failed — try to use raw body
          return body
        end

        deserialize_data(data, return_type)
      rescue StandardError => e
        logger.error("Failed to deserialize data into #{return_type}: #{e.message}")
        nil
      end

      # Force refresh authentication token (called on 401/403 errors)
      # @return [Boolean] true if token was successfully refreshed, false otherwise
      def force_refresh_auth_token
        return false unless @configuration.auth_configured?

        @token_refresh_mutex.synchronize do
          # Skip backoff for legitimate token renewal (credentials should be valid)
          token = get_new_token(skip_backoff: true)
          if token
            @configuration.update_token(token)
            return true
          end

          # Check if auth was disabled during token refresh (404 response)
          unless @configuration.auth_configured?
            logger.info('Authentication was disabled (no auth endpoint found)')
            return false
          end

          false
        end
      end

      # Get authentication headers for requests
      # @return [Hash, nil] Headers hash with X-Authorization or nil
      def get_authentication_headers
        return nil unless @configuration.auth_token

        now_ms = (Time.now.to_f * 1000).round
        time_since_last_update = now_ms - @configuration.token_update_time

        # Proactively refresh token if TTL expired
        if time_since_last_update > @configuration.auth_token_ttl_msec
          @token_refresh_mutex.synchronize do
            logger.info('Authentication token TTL expired, renewing token...')
            token = get_new_token(skip_backoff: true)
            @configuration.update_token(token) if token
            logger.debug('Authentication token successfully renewed') if token
          end
        end

        { 'X-Authorization' => @configuration.auth_token }
      end

      private

      # Call API without automatic retry (internal method)
      def call_api_no_retry(resource_path, method, opts = {})
        path_params = opts[:path_params] || {}
        query_params = opts[:query_params] || {}
        header_params = (opts[:header_params] || {}).merge(@default_headers)
        body = opts[:body]
        return_type = opts[:return_type]
        return_http_data_only = opts[:return_http_data_only] || false

        # Replace path parameters
        path_params.each do |key, value|
          resource_path = resource_path.sub("{#{key}}", URI.encode_www_form_component(value.to_s))
        end

        # Add authentication headers (skip for /token endpoint)
        if @configuration.auth_configured? && resource_path != '/token'
          auth_headers = get_authentication_headers
          header_params.merge!(auth_headers) if auth_headers
        end

        # Sanitize body for serialization
        body = sanitize_for_serialization(body) if body

        # Build full URL
        url = @configuration.server_url + resource_path

        # Make HTTP request
        response = @rest_client.request(
          method.to_s.upcase,
          url,
          query: query_params,
          headers: header_params,
          body: body ? JSON.generate(body) : nil
        )

        @last_response = response

        # Deserialize response
        return_data = return_type ? deserialize(response, return_type) : nil

        if return_http_data_only
          return_data
        else
          [return_data, response.status, response.headers]
        end
      end

      # Wrapper to handle auth retry
      alias call_api_with_retry call_api_no_retry

      # Refresh authentication token on initialization
      def refresh_auth_token
        return if @configuration.auth_token
        return unless @configuration.auth_configured?

        @token_refresh_mutex.synchronize do
          token = get_new_token(skip_backoff: false)
          @configuration.update_token(token) if token || @configuration.auth_configured?
        end
      end

      # Get new token from server with exponential backoff
      # @param [Boolean] skip_backoff Skip backoff logic for legitimate renewals
      # @return [String, nil] Token string or nil
      def get_new_token(skip_backoff: false)
        # Apply backoff only if not skipping and we have failures
        unless skip_backoff
          if @token_refresh_failures >= @max_token_refresh_failures
            logger.error(
              "Token refresh has failed #{@token_refresh_failures} times. " \
              'Please check your authentication credentials. ' \
              'Stopping token refresh attempts.'
            )
            return nil
          end

          # Exponential backoff: 2^failures seconds
          if @token_refresh_failures.positive?
            now = Time.now.to_f
            backoff_seconds = 2**@token_refresh_failures
            time_since_last_attempt = now - @last_token_refresh_attempt

            if time_since_last_attempt < backoff_seconds
              remaining = backoff_seconds - time_since_last_attempt
              logger.warn(
                "Token refresh backoff active. Please wait #{remaining.round(1)}s before next attempt. " \
                "(Failure count: #{@token_refresh_failures})"
              )
              return nil
            end
          end
        end

        @last_token_refresh_attempt = Time.now.to_f

        begin
          key_id = @configuration.authentication_settings.key_id
          key_secret = @configuration.authentication_settings.key_secret

          if key_id.nil? || key_secret.nil?
            logger.error('Authentication Key or Secret is not set. Failed to get the auth token')
            @token_refresh_failures += 1
            return nil
          end

          logger.debug('Requesting new authentication token from server')
          
          response = call_api_no_retry(
            '/token',
            'POST',
            header_params: { 'Content-Type' => 'application/json' },
            body: { keyId: key_id, keySecret: key_secret },
            return_type: 'Token',
            return_http_data_only: true
          )

          # Success - reset failure counter
          @token_refresh_failures = 0
          response.token

        rescue AuthorizationError => e
          # 401 from /token endpoint - invalid credentials
          @token_refresh_failures += 1
          logger.error(
            "Authentication failed when getting token (attempt #{@token_refresh_failures}): " \
            "#{e.status} - #{e.code}. " \
            'Please check your CONDUCTOR_AUTH_KEY and CONDUCTOR_AUTH_SECRET. ' \
            "Will retry with exponential backoff (#{2**@token_refresh_failures}s)."
          )
          nil

        rescue ApiError => e
          # Check if it's a 404 - indicates no authentication endpoint (Conductor OSS)
          if e.not_found?
            logger.info(
              'Authentication endpoint /token not found (404). ' \
              'Running in open mode without authentication (Conductor OSS).'
            )
            # Disable authentication to prevent future attempts
            @configuration.disable_auth!
            # Reset failure counter since this is not a failure
            @token_refresh_failures = 0
            nil
          else
            # Other API errors
            @token_refresh_failures += 1
            logger.error(
              "API error when getting token (attempt #{@token_refresh_failures}): " \
              "#{e.status} - #{e.reason}"
            )
            nil
          end

        rescue StandardError => e
          # Other errors (network, etc)
          @token_refresh_failures += 1
          logger.error("Failed to get new token (attempt #{@token_refresh_failures}): #{e.message}")
          nil
        end
      end

      # Deserialize data into specified type
      # @param [Object] data Data to deserialize
      # @param [String] type_string Type string (e.g., 'Task', 'Array<Task>', 'Hash<String, Integer>')
      # @return [Object] Deserialized object
      def deserialize_data(data, type_string)
        return nil if data.nil?

        # Handle Array types: Array<Type>
        if type_string.start_with?('Array<')
          sub_type = type_string[6..-2] # Extract Type from Array<Type>
          return data.map { |item| deserialize_data(item, sub_type) } if data.is_a?(Array)
        end

        # Handle Hash types: Hash<KeyType, ValueType>
        if type_string.start_with?('Hash<')
          match = type_string.match(/Hash<([^,]+),\s*(.+)>/)
          if match
            _key_type = match[1]
            value_type = match[2]
            return data.transform_values { |v| deserialize_data(v, value_type) } if data.is_a?(Hash)
          end
        end

        # Handle primitive types
        case type_string
        when 'String'
          data.to_s
        when 'Integer'
          data.to_i
        when 'Float'
          data.to_f
        when 'Boolean'
          data == true || data.to_s.downcase == 'true'
        when 'DateTime'
          DateTime.parse(data.to_s)
        when 'Date'
          Date.parse(data.to_s)
        when 'Time'
          Time.parse(data.to_s)
        when 'Object'
          data
        else
          # Try to deserialize as a model class
          deserialize_model(data, type_string)
        end
      end

      # Deserialize data into model class
      # @param [Hash] data Data hash
      # @param [String] class_name Model class name
      # @return [Object] Model instance
      def deserialize_model(data, class_name)
        return data unless data.is_a?(Hash)

        # Try to get the model class from Conductor::Http::Models
        klass = begin
          Conductor::Http::Models.const_get(class_name)
        rescue NameError
          return data
        end

        # Use BaseModel.from_hash if available
        if klass.respond_to?(:from_hash)
          klass.from_hash(data)
        else
          data
        end
      end

      # Get default headers
      def get_default_headers
        {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        }
      end

      # Get logger
      def logger
        @logger ||= begin
          require 'logger'
          Logger.new($stdout, level: Logger::INFO)
        end
      end
    end
  end
end

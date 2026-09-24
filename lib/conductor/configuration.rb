# frozen_string_literal: true

require_relative 'configuration/authentication_settings'

module Conductor
  # Configuration for Conductor client
  class Configuration
    # Legacy process-wide token cache. Tokens are now cached per Configuration
    # instance so that two configurations (different servers or credentials) in
    # one process never share a token. The class-level accessors remain for one
    # release as a compatibility shim and warn once when used.
    @auth_token = nil
    @token_update_time = 0

    class << self
      def auth_token
        legacy_token_cache_warning
        @auth_token
      end

      def auth_token=(token)
        legacy_token_cache_warning
        @auth_token = token
      end

      def token_update_time
        legacy_token_cache_warning
        @token_update_time
      end

      def token_update_time=(time)
        legacy_token_cache_warning
        @token_update_time = time
      end

      private

      def legacy_token_cache_warning
        return if @legacy_token_cache_warned

        @legacy_token_cache_warned = true
        warn '[Conductor] Configuration.auth_token / token_update_time are deprecated: ' \
             'the auth token is cached per Configuration instance.'
      end
    end

    attr_accessor :base_url, :server_api_url, :debug, :authentication_settings,
                  :verify_ssl, :ssl_ca_cert, :cert_file, :key_file,
                  :proxy, :auth_token_ttl_min

    attr_reader :host, :ui_host

    def initialize(base_url: nil, server_api_url: nil, debug: false,
                   authentication_settings: nil, auth_key: nil, auth_secret: nil,
                   auth_token_ttl_min: 45, verify_ssl: true)
      @debug = debug
      @verify_ssl = verify_ssl
      @ssl_ca_cert = nil
      @cert_file = nil
      @key_file = nil
      @proxy = nil
      @auth_token_ttl_min = auth_token_ttl_min
      @auth_token = nil
      @token_update_time = 0

      # Resolve server URL
      @host = resolve_host(server_api_url, base_url)
      @ui_host = resolve_ui_host

      # Resolve authentication
      @authentication_settings = resolve_auth_settings(authentication_settings, auth_key, auth_secret)
    end

    def auth_token_ttl_msec
      @auth_token_ttl_min * 60 * 1000
    end

    def auth_configured?
      @authentication_settings&.configured? || false
    end

    def disable_auth!
      @authentication_settings = nil
    end

    # Cache an auth token on this configuration instance
    # @param token [String] JWT returned by the /token endpoint
    def update_token(token)
      @auth_token = token
      @token_update_time = (Time.now.to_f * 1000).to_i
    end

    # @return [String, nil] The cached auth token for this configuration
    attr_reader :auth_token

    # @return [Integer] Epoch milliseconds of the last token update (0 when never set)
    attr_reader :token_update_time

    # Alias for server URL (used in some places)
    def server_url
      @host
    end

    private

    def resolve_host(server_api_url, base_url)
      return server_api_url if server_api_url
      return "#{base_url}/api" if base_url

      # Fall back to environment variable or default
      env_url = ENV.fetch('CONDUCTOR_SERVER_URL', nil)
      return env_url if env_url

      'http://localhost:8080/api'
    end

    def resolve_ui_host
      env_ui_url = ENV.fetch('CONDUCTOR_UI_SERVER_URL', nil)
      return env_ui_url if env_ui_url

      # Derive UI host from API host
      @host.sub(%r{/api$}, '')
    end

    def resolve_auth_settings(auth_settings, auth_key, auth_secret)
      return auth_settings if auth_settings

      # Try explicit parameters first
      return AuthenticationSettings.new(key_id: auth_key, key_secret: auth_secret) if auth_key && auth_secret

      # Try environment variables
      settings = AuthenticationSettings.new
      settings.configured? ? settings : nil
    end
  end
end

# frozen_string_literal: true

module Conductor
  # Authentication settings for Conductor server
  class AuthenticationSettings
    attr_accessor :key_id, :key_secret

    def initialize(key_id: nil, key_secret: nil)
      @key_id = key_id || ENV.fetch('CONDUCTOR_AUTH_KEY', nil)
      @key_secret = key_secret || ENV.fetch('CONDUCTOR_AUTH_SECRET', nil)
    end

    def configured?
      !key_id.nil? && !key_secret.nil? && !key_id.empty? && !key_secret.empty?
    end
  end
end

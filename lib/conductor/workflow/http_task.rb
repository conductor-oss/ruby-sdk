# frozen_string_literal: true

module Conductor
  module Workflow
    # HTTP methods for HttpTask
    module HttpMethod
      GET = 'GET'
      PUT = 'PUT'
      POST = 'POST'
      DELETE = 'DELETE'
      HEAD = 'HEAD'
      OPTIONS = 'OPTIONS'
      PATCH = 'PATCH'
    end

    # HttpInput represents the configuration for an HTTP request
    class HttpInput
      attr_accessor :uri, :method, :headers, :accept, :content_type,
                    :connection_time_out, :read_timeout, :body

      # Create a new HttpInput
      # @param method [String] HTTP method (GET, POST, PUT, DELETE, etc.)
      # @param uri [String] The URI to call
      # @param headers [Hash<String, Array<String>>] Request headers
      # @param accept [String] Accept header value
      # @param content_type [String] Content-Type header value
      # @param connection_time_out [Integer] Connection timeout in milliseconds
      # @param read_timeout [Integer] Read timeout in milliseconds
      # @param body [Object] Request body
      def initialize(method: HttpMethod::GET, uri: nil, headers: nil, accept: nil,
                     content_type: nil, connection_time_out: nil, read_timeout: nil, body: nil)
        @method = method
        @uri = uri
        @headers = headers
        @accept = accept
        @content_type = content_type
        @connection_time_out = connection_time_out
        @read_timeout = read_timeout
        @body = body
      end

      # Convert to hash for serialization
      # @return [Hash] The HTTP input as a hash
      def to_h
        result = {}
        result['uri'] = @uri if @uri
        result['method'] = @method if @method
        result['headers'] = @headers if @headers
        result['accept'] = @accept if @accept
        result['contentType'] = @content_type if @content_type
        result['connectionTimeOut'] = @connection_time_out if @connection_time_out
        result['readTimeOut'] = @read_timeout if @read_timeout
        result['body'] = @body if @body
        result
      end
    end

    # HttpTask makes HTTP calls as part of a workflow
    class HttpTask < TaskInterface
      # Create a new HttpTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param http_input [HttpInput, Hash] HTTP request configuration
      # @example With HttpInput object
      #   http_input = HttpInput.new(method: 'GET', uri: 'https://api.example.com/users')
      #   task = HttpTask.new('fetch_users', http_input)
      # @example With hash
      #   task = HttpTask.new('fetch_users', { uri: 'https://api.example.com/users', method: 'GET' })
      def initialize(task_ref_name, http_input)
        http_hash = case http_input
                    when HttpInput
                      http_input.to_h
                    when Hash
                      # Ensure method has a default
                      http_input['method'] ||= http_input[:method] || HttpMethod::GET
                      http_input
                    else
                      raise ArgumentError, "http_input must be an HttpInput or Hash, got #{http_input.class}"
                    end

        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::HTTP,
          input_parameters: { 'http_request' => http_hash }
        )
      end

      # Get reference to HTTP response status code
      # @return [String] Expression for status code
      def status_code
        "${#{task_reference_name}.output.response.statusCode}"
      end

      # Get reference to HTTP response headers
      # @param json_path [String, nil] Optional path to specific header
      # @return [String] Expression for headers
      def response_headers(json_path = nil)
        if json_path.nil?
          "${#{task_reference_name}.output.response.headers}"
        else
          "${#{task_reference_name}.output.response.headers.#{json_path}}"
        end
      end

      # Get reference to HTTP response body
      # @param json_path [String, nil] Optional path within body
      # @return [String] Expression for body
      def body(json_path = nil)
        if json_path.nil?
          "${#{task_reference_name}.output.response.body}"
        else
          "${#{task_reference_name}.output.response.body.#{json_path}}"
        end
      end
    end
  end
end

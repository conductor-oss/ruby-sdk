# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Response from bulk workflow operations
      class BulkResponse < BaseModel
        SWAGGER_TYPES = {
          bulk_error_results: 'Hash<String, String>',
          bulk_successful_results: 'Array<String>'
        }.freeze

        ATTRIBUTE_MAP = {
          bulk_error_results: :bulkErrorResults,
          bulk_successful_results: :bulkSuccessfulResults
        }.freeze

        attr_accessor :bulk_error_results, :bulk_successful_results

        def initialize(params = {})
          @bulk_error_results = params[:bulk_error_results] || {}
          @bulk_successful_results = params[:bulk_successful_results] || []
        end

        # Check if any errors occurred
        # @return [Boolean]
        def errors?
          !@bulk_error_results.empty?
        end

        # Check if all operations succeeded
        # @return [Boolean]
        def all_successful?
          @bulk_error_results.empty?
        end
      end
    end
  end
end

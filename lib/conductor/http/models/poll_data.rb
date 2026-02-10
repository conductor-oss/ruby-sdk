# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Poll data for a task queue
      class PollData < BaseModel
        SWAGGER_TYPES = {
          queue_name: 'String',
          domain: 'String',
          worker_id: 'String',
          last_poll_time: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          queue_name: :queueName,
          domain: :domain,
          worker_id: :workerId,
          last_poll_time: :lastPollTime
        }.freeze

        attr_accessor :queue_name, :domain, :worker_id, :last_poll_time

        def initialize(params = {})
          @queue_name = params[:queue_name]
          @domain = params[:domain]
          @worker_id = params[:worker_id]
          @last_poll_time = params[:last_poll_time]
        end
      end
    end
  end
end

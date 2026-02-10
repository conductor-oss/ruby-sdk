# frozen_string_literal: true

module Conductor
  module Workflow
    # KafkaPublishTask publishes messages to a Kafka topic
    class KafkaPublishTask < TaskInterface
      # Create a new KafkaPublishTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param topic [String] Kafka topic name
      # @param value [Object] Message value (or expression)
      # @param key [Object, nil] Message key (optional)
      # @param headers [Hash, nil] Message headers (optional)
      # @param boot_strap_servers [String, nil] Kafka bootstrap servers (optional)
      def initialize(task_ref_name, topic:, value:, key: nil, headers: nil, boot_strap_servers: nil)
        kafka_request = {
          'topic' => topic,
          'value' => value
        }
        kafka_request['key'] = key if key
        kafka_request['headers'] = headers if headers
        kafka_request['bootStrapServers'] = boot_strap_servers if boot_strap_servers

        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::KAFKA_PUBLISH,
          input_parameters: { 'kafka_request' => kafka_request }
        )
      end
    end
  end
end

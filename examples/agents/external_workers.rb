# frozen_string_literal: true

# Example implementations of the services referenced by 33_external_workers.rb.
# Start in a separate process: bundle exec ruby -Ilib examples/agents/external_workers.rb
require 'conductor/agents'

module ExternalWorkerServices
  def self.start(configuration: Conductor::Configuration.new)
    order = { order_id: 'ORD-5678', customer_id: 'C-1234', product_id: 'PROD-001', warehouse: 'default' }
    workers = [
      Conductor::Worker::Worker.new('get_customer', lambda { |task|
        { customer_id: task.input_data['customer_id'], name: 'Example Customer', orders: [order.merge(status: 'pending')] }
      }, register_task_def: true),
      Conductor::Worker::Worker.new('check_inventory', lambda { |task|
        { product_id: task.input_data['product_id'], warehouse: task.input_data.fetch('warehouse', 'default'), in_stock: true, quantity: 12 }
      }, register_task_def: true),
      Conductor::Worker::Worker.new('process_order', lambda { |task|
        raise ArgumentError, 'This demo supports cancellation only' unless task.input_data['action'] == 'cancel'

        order.merge(order_id: task.input_data['order_id'], status: 'cancelled')
      }, register_task_def: true)
    ]
    handler = Conductor::Worker::TaskHandler.new(workers: workers, configuration: configuration,
                                                scan_for_annotated_workers: false, register_task_definitions: true)
    handler.start
    handler
  end
end

if $PROGRAM_NAME == __FILE__
  handler = ExternalWorkerServices.start
  begin
    stop = Queue.new
    %w[INT TERM].each { |signal| trap(signal) { stop << true } }
    stop.pop
  ensure
    handler.stop
  end
end

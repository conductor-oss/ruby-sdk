# frozen_string_literal: true

# Greetings Worker
# ================
# Simple worker that creates a greeting message.
# For detailed explanation: https://github.com/conductor-oss/ruby-sdk

require_relative '../../lib/conductor'

# Worker that creates a greeting message
class GreetingsWorker
  include Conductor::Worker::WorkerModule

  worker_task 'greet'

  def execute(task)
    name = get_input(task, 'name', 'World')
    greeting = "Hello, #{name}!"

    puts "[GreetingsWorker] Created greeting: #{greeting}"

    { 'result' => greeting }
  end
end

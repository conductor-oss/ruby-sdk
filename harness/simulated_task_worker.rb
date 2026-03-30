# frozen_string_literal: true

require 'securerandom'

module Harness
  # SimulatedTaskWorker -- a configurable worker that simulates work
  # by sleeping for a delay, optionally failing, and producing structured output.
  #
  # Supports multiple delay distributions (fixed, random, normal, exponential)
  # and failure modes (random, conditional, sequential) controlled via task input.
  class SimulatedTaskWorker
    ALPHANUMERIC = ('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a

    attr_reader :task_name, :codename, :default_delay_ms, :batch_size, :poll_interval_ms, :worker_id

    def initialize(task_name, codename, sleep_seconds, batch_size: 20, poll_interval_ms: 100)
      @task_name = task_name
      @codename = codename
      @default_delay_ms = sleep_seconds * 1000
      @batch_size = batch_size
      @poll_interval_ms = poll_interval_ms
      @rng = Random.new

      instance_id = ENV['HOSTNAME'] || SecureRandom.hex(4)
      @worker_id = "#{task_name}-#{instance_id}"

      puts "[#{task_name}] Initialized worker " \
           "[workerId=#{@worker_id}, codename=#{codename}, " \
           "batchSize=#{batch_size}, pollInterval=#{poll_interval_ms}ms]"
    end

    # Execute a polled task. Called by the SDK's TaskRunner.
    # @param task [Conductor::Http::Models::Task]
    # @return [Hash] output data (SDK converts Hash returns to COMPLETED TaskResult)
    def execute(task)
      input = task.input_data || {}
      task_id = task.task_id
      task_index = to_int(input['taskIndex'], -1)

      puts "[#{@task_name}] Starting simulated task " \
           "[id=#{task_id}, index=#{task_index}, codename=#{@codename}]"

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      delay_type = (input['delayType'] || 'fixed').to_s
      min_delay = to_int(input['minDelay'], @default_delay_ms)
      max_delay = to_int(input['maxDelay'], min_delay + 100)
      mean_delay = to_int(input['meanDelay'], (min_delay + max_delay) / 2)
      std_deviation = to_int(input['stdDeviation'], 30)
      success_rate = to_float(input['successRate'], 1.0)
      failure_mode = (input['failureMode'] || 'random').to_s
      output_size = to_int(input['outputSize'], 1024)

      delay_ms = 0
      unless delay_type.downcase == 'wait'
        delay_ms = calculate_delay(delay_type, min_delay, max_delay, mean_delay, std_deviation)

        puts "[#{@task_name}] Simulated task [id=#{task_id}, index=#{task_index}] " \
             "sleeping for #{delay_ms} ms"
        sleep(delay_ms / 1000.0)
      end

      unless should_task_succeed?(success_rate, failure_mode, input)
        puts "[#{@task_name}] Simulated task [id=#{task_id}, index=#{task_index}] " \
             'failed as configured'
        raise SimulatedTaskError, 'Simulated task failure based on configuration'
      end

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      generate_output(input, task_id, task_index, delay_ms, elapsed_ms, output_size)
    end

    private

    # ----- delay calculation -----

    def calculate_delay(delay_type, min_delay, max_delay, mean_delay, std_deviation)
      case delay_type.downcase
      when 'fixed'
        min_delay
      when 'random'
        range = [max_delay - min_delay + 1, 1].max
        min_delay + @rng.rand(range)
      when 'normal'
        gaussian = next_gaussian
        [1, (mean_delay + gaussian * std_deviation).round].max
      when 'exponential'
        exp = -mean_delay * Math.log(1 - @rng.rand)
        [[min_delay, exp.to_i].max, max_delay].min
      else
        min_delay
      end
    end

    # Box-Muller transform
    def next_gaussian
      u1 = 1.0 - @rng.rand
      u2 = @rng.rand
      Math.sqrt(-2.0 * Math.log(u1)) * Math.sin(2.0 * Math::PI * u2)
    end

    # ----- failure logic -----

    def should_task_succeed?(success_rate, failure_mode, input)
      force_success = to_bool_or_nil(input['forceSuccess'])
      return force_success unless force_success.nil?

      force_fail = to_bool_or_nil(input['forceFail'])
      return !force_fail unless force_fail.nil?

      case failure_mode.downcase
      when 'random'
        @rng.rand < success_rate
      when 'conditional'
        task_index = to_int(input['taskIndex'], -1)
        if task_index >= 0
          fail_indexes = input['failIndexes']
          if fail_indexes.is_a?(Array)
            return false if fail_indexes.any? { |i| i.to_s == task_index.to_s }
          end

          fail_every = to_int(input['failEvery'], 0)
          return false if fail_every.positive? && (task_index % fail_every).zero?
        end
        @rng.rand < success_rate
      when 'sequential'
        attempt = to_int(input['attempt'], 1)
        fail_until = to_int(input['failUntilAttempt'], 2)
        attempt >= fail_until
      else
        @rng.rand < success_rate
      end
    end

    # ----- output generation -----

    def generate_output(input, task_id, task_index, delay_ms, elapsed_ms, output_size)
      output = {
        'taskId' => task_id,
        'taskIndex' => task_index,
        'codename' => @codename,
        'status' => 'completed',
        'configuredDelayMs' => delay_ms,
        'actualExecutionTimeMs' => elapsed_ms,
        'a_or_b' => @rng.rand(100) > 20 ? 'a' : 'b',
        'c_or_d' => @rng.rand(100) > 33 ? 'c' : 'd'
      }

      output['input'] = input if to_bool(input['includeInput'], false)

      prev = input['previousTaskOutput']
      output['previousTaskData'] = prev unless prev.nil?

      output['data'] = generate_random_data(output_size) if output_size.positive?

      template = input['outputTemplate']
      if template.is_a?(Hash)
        template.each { |k, v| output[k] = v }
      end

      output
    end

    def generate_random_data(size)
      return '' if size <= 0

      Array.new(size) { ALPHANUMERIC[@rng.rand(ALPHANUMERIC.length)] }.join
    end

    # ----- type coercion helpers -----

    def to_int(value, default)
      return default if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      default
    end

    def to_float(value, default)
      return default if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      default
    end

    def to_bool(value, default)
      return default if value.nil?
      return value if [true, false].include?(value)

      value.to_s.downcase == 'true'
    end

    def to_bool_or_nil(value)
      return nil if value.nil?
      return value if [true, false].include?(value)

      case value.to_s.downcase
      when 'true' then true
      when 'false' then false
      end
    end
  end

  class SimulatedTaskError < StandardError; end
end

# frozen_string_literal: true

require 'conductor/agents'

# The weather tool from the one-pager. The description and result must match what was
# recorded in conductor-mocks agent/tool_happy_path.
module WeatherTools
  extend Conductor::Agents::Tools

  tool def get_weather(city: String, units: 'metric')
    { temp_c: 21.0, summary: "Sunny in #{city}" }
  end
  describe :get_weather, 'Get the current weather for a city.'
end

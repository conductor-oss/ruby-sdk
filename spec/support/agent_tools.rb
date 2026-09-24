# frozen_string_literal: true

# Tool definitions used by the agents specs. They live in a real file so the
# Tools DSL can read keyword defaults and secret() literals from the AST.
require 'conductor/agents'

module SpecTools
  module Weather
    extend Conductor::Agents::Tools

    tool def current(city: String, units: 'metric')
      { temp_c: 21.0, summary: "Sunny in #{city} (#{units})" }
    end

    tool def forecast(city: String, days: 3, detailed: false, tags: [String], mode: %w[brief full], ratio: 0.5,
                      extra: nil, opts: {})
      { city: city, days: days, detailed: detailed, tags: tags, mode: mode, ratio: ratio, extra: extra, opts: opts }
    end
    describe :forecast, 'Multi-day forecast.'
  end

  module Github
    extend Conductor::Agents::Tools

    tool def create_issue(title: String, body: '')
      { title: title, body: body, token: secret('GH_TOKEN') }
    end

    tool def gh_cli(title: String)
      secrets_env('GH_TOKEN', 'GH_HOST')
    end

    tool def dynamic_secret(name: String)
      secret(name)
    end
    requires_approval :create_issue
  end

  module Plain
    extend Conductor::Agents::Tools

    tool def lookup(city:, units: 'metric')
      [city, units]
    end
  end

  module Refunds
    extend Conductor::Agents::Tools

    tool def issue_refund(order_id: String, amount: Float)
      { refunded: amount, order_id: order_id }
    end
    requires_approval :issue_refund

    def self.positional(city, units: 'metric')
      [city, units]
    end
  end
end

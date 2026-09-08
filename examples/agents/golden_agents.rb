# frozen_string_literal: true

# The 19 agents whose serialized agentConfig must match the Python SDK byte for byte
# (spec/fixtures/agents/configs/*.json, vendored from python-sdk examples/agents/_configs).
#
# Used by spec/conductor/agents/contract_spec.rb and by dump_agent_configs.rb.
# Each example keeps its tools in its own module so that tools with the same name but
# different descriptions (get_weather in 02 vs 03) do not collide.
require 'conductor/agents'

module GoldenAgents
  MODEL = ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'anthropic/claude-sonnet-4-6')
  A = Conductor::Agents

  module Ex02
    extend A::Tools
    tool def get_weather(city: String)
      {}
    end
    describe :get_weather, 'Get current weather for a city.'
    tool def calculate(expression: String)
      {}
    end
    describe :calculate, 'Evaluate a math expression.'
    tool def send_email(to: String, subject: String, body: String)
      {}
    end
    describe :send_email, 'Send an email.'
    requires_approval :send_email
    self[:send_email].timeout_seconds = 60
  end

  module Ex03
    extend A::Tools
    tool def get_weather(city: String)
      {}
    end
    describe :get_weather, 'Get current weather data for a city.'
  end

  module Ex05
    extend A::Tools
    tool def check_balance(account_id: String)
      {}
    end
    describe :check_balance, 'Check the balance of a bank account.'
    tool def lookup_order(order_id: String)
      {}
    end
    describe :lookup_order, 'Look up the status of an order.'
    tool def get_pricing(product: String)
      {}
    end
    describe :get_pricing, 'Get pricing information for a product.'
  end

  module Ex10
    extend A::Tools
    tool def get_order_status(order_id: String)
      {}
    end
    describe :get_order_status, 'Look up the current status of an order.'
    tool def get_customer_info(customer_id: String)
      {}
    end
    describe :get_customer_info, 'Retrieve customer details including payment info on file.'
  end

  module Ex19
    extend A::Tools
    tool def search(query: String)
      ''
    end
    describe :search, 'Search for information.'
    self[:search].output_schema = { 'type' => 'string' }
  end

  module Ex21
    extend A::Tools
    tool def get_user_profile(user_id: String)
      {}
    end
    describe :get_user_profile, "Retrieve a user's profile from the database."
  end

  module Ex45
    extend A::Tools
    tool def search_knowledge_base(query: String)
      {}
    end
    describe :search_knowledge_base, 'Search an internal knowledge base for information.'
    tool def calculate(expression: String)
      {}
    end
    describe :calculate, 'Evaluate a math expression safely.'
  end

  module Ex47
    extend A::Tools
    tool def get_facts(topic: String)
      {}
    end
    describe :get_facts, 'Get interesting facts about a topic.'
  end

  # 47_callbacks: before_model / after_model hooks
  class MonitorHandler < A::CallbackHandler
    def on_model_start(**_kwargs)
      {}
    end

    def on_model_end(**_kwargs)
      {}
    end
  end

  EXAMPLES = {
    '01_basic_agent' => lambda {
      A::Agent.new(name: 'greeter', model: MODEL)
    },

    '02_tools' => lambda {
      A::Agent.new(
        name: 'tool_demo_agent', model: MODEL,
        tools: [Ex02[:get_weather], Ex02[:calculate], Ex02[:send_email]],
        instructions: 'You are a helpful assistant with access to weather, calculator, and email tools.'
      )
    },

    '03_structured_output' => lambda {
      weather_report = {
        'title' => 'WeatherReport',
        'type' => 'object',
        'properties' => {
          'city' => { 'title' => 'City', 'type' => 'string' },
          'temperature' => { 'title' => 'Temperature', 'type' => 'number' },
          'condition' => { 'title' => 'Condition', 'type' => 'string' },
          'recommendation' => { 'title' => 'Recommendation', 'type' => 'string' }
        },
        'required' => %w[city temperature condition recommendation]
      }
      A::Agent.new(
        name: 'weather_reporter', model: MODEL, tools: [Ex03[:get_weather]], output_type: weather_report,
        instructions: 'You are a weather reporter. Get the weather and provide a recommendation.'
      )
    },

    '05_handoffs' => lambda {
      billing = A::Agent.new(name: 'billing', model: MODEL, tools: [Ex05[:check_balance]],
                             instructions: 'You handle billing questions: balances, payments, invoices.')
      technical = A::Agent.new(name: 'technical', model: MODEL, tools: [Ex05[:lookup_order]],
                               instructions: 'You handle technical questions: order status, shipping, returns.')
      sales = A::Agent.new(name: 'sales', model: MODEL, tools: [Ex05[:get_pricing]],
                           instructions: 'You handle sales questions: pricing, products, promotions.')
      A::Agent.new(name: 'support', model: MODEL, agents: [billing, technical, sales], strategy: :handoff,
                   instructions: 'Route customer requests to the right specialist: billing, technical, or sales.')
    },

    '06_sequential_pipeline' => lambda {
      researcher = A::Agent.new(
        name: 'researcher', model: MODEL,
        instructions: 'You are a researcher. Given a topic, provide key facts and data points. ' \
                      'Be thorough but concise. Output raw research findings.'
      )
      writer = A::Agent.new(
        name: 'writer', model: MODEL,
        instructions: 'You are a writer. Take research findings and write a clear, engaging ' \
                      'article. Use headers and bullet points where appropriate.'
      )
      editor = A::Agent.new(
        name: 'editor', model: MODEL,
        instructions: 'You are an editor. Review the article for clarity, grammar, and tone. ' \
                      'Make improvements and output the final polished version.'
      )
      researcher >> writer >> editor
    },

    '07_parallel_agents' => lambda {
      market = A::Agent.new(
        name: 'market_analyst', model: MODEL,
        instructions: 'You are a market analyst. Analyze the given topic from a market perspective: ' \
                      'market size, growth trends, key players, and opportunities.'
      )
      risk = A::Agent.new(
        name: 'risk_analyst', model: MODEL,
        instructions: 'You are a risk analyst. Analyze the given topic for risks: ' \
                      'regulatory risks, technical risks, competitive threats, and mitigation strategies.'
      )
      compliance = A::Agent.new(
        name: 'compliance', model: MODEL,
        instructions: 'You are a compliance specialist. Check the given topic for compliance considerations: ' \
                      'data privacy, regulatory requirements, and industry standards.'
      )
      A::Agent.new(name: 'analysis', model: MODEL, agents: [market, risk, compliance], strategy: :parallel)
    },

    '08_router_agent' => lambda {
      planner = A::Agent.new(name: 'planner', model: MODEL,
                             instructions: 'You create implementation plans. Break down tasks into clear numbered steps.')
      coder = A::Agent.new(name: 'coder', model: MODEL,
                           instructions: 'You write code. Output clean, well-documented Python code.')
      reviewer = A::Agent.new(name: 'reviewer', model: MODEL,
                              instructions: 'You review code. Check for bugs, style issues, and suggest improvements.')
      A::Agent.new(
        name: 'dev_team', model: MODEL, agents: [planner, coder, reviewer], strategy: :router, router: planner,
        instructions: 'You are the tech lead. Route requests to the right team member: ' \
                      'planner for design/architecture, coder for implementation, reviewer for code review.'
      )
    },

    '10_guardrails' => lambda {
      no_pii = A::Guardrail.new(name: 'no_pii', position: :output, on_fail: :retry) do |content|
        if content =~ /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/ || content =~ /\b\d{3}-\d{2}-\d{4}\b/
          A::GuardrailResult.new(passed: false, message: 'Your response contains PII. Redact it.')
        else
          A::GuardrailResult.new(passed: true)
        end
      end
      A::Agent.new(
        name: 'support_agent', model: MODEL, tools: [Ex10[:get_order_status], Ex10[:get_customer_info]],
        guardrails: [no_pii],
        instructions: 'You are a customer support assistant. Use the available tools to ' \
                      'answer questions about orders and customers. Always include all ' \
                      'details from the tool results in your response.'
      )
    },

    '13_hierarchical_agents' => lambda {
      backend = A::Agent.new(
        name: 'backend_dev', model: MODEL,
        instructions: 'You are a backend developer. You design APIs, databases, and server ' \
                      'architecture. Provide technical recommendations with code examples.'
      )
      frontend = A::Agent.new(
        name: 'frontend_dev', model: MODEL,
        instructions: 'You are a frontend developer. You design UI components, user flows, ' \
                      'and client-side architecture. Provide recommendations with code examples.'
      )
      content = A::Agent.new(
        name: 'content_writer', model: MODEL,
        instructions: 'You are a content writer. You create blog posts, landing page copy, ' \
                      'and marketing materials. Write engaging, clear content.'
      )
      seo = A::Agent.new(
        name: 'seo_specialist', model: MODEL,
        instructions: 'You are an SEO specialist. You optimize content for search engines, ' \
                      'suggest keywords, and improve page rankings.'
      )
      engineering = A::Agent.new(
        name: 'engineering_lead', model: MODEL, agents: [backend, frontend], strategy: :handoff,
        instructions: 'You are the engineering lead. Route technical questions to the right ' \
                      'specialist: backend_dev for APIs/databases/servers, frontend_dev for UI/UX/client-side.'
      )
      marketing = A::Agent.new(
        name: 'marketing_lead', model: MODEL, agents: [content, seo], strategy: :handoff,
        instructions: 'You are the marketing lead. Route marketing questions to the right ' \
                      'specialist: content_writer for blog posts/copy, seo_specialist for SEO/keywords/rankings.'
      )
      A::Agent.new(
        name: 'ceo', model: MODEL, agents: [engineering, marketing], strategy: :swarm,
        handoffs: [
          A::Handoff::OnTextMention.new(target: 'engineering_lead', text: 'engineering_lead'),
          A::Handoff::OnTextMention.new(target: 'marketing_lead', text: 'marketing_lead')
        ],
        instructions: 'You are the CEO. Route requests to the right department: ' \
                      'engineering_lead for technical/development questions, ' \
                      'marketing_lead for marketing/content/SEO questions.'
      )
    },

    '17_swarm_orchestration' => lambda {
      refund = A::Agent.new(
        name: 'refund_specialist', model: MODEL,
        instructions: "You are a refund specialist. Process the customer's refund request. " \
                      'Check eligibility, confirm the refund amount, and let them know the ' \
                      'timeline. Be empathetic and clear. Do NOT ask follow-up questions -- ' \
                      'just process the refund based on what the customer told you.'
      )
      tech = A::Agent.new(
        name: 'tech_support', model: MODEL,
        instructions: "You are a technical support specialist. Diagnose the customer's " \
                      'technical issue and provide clear troubleshooting steps.'
      )
      A::Agent.new(
        name: 'support', model: MODEL, agents: [refund, tech], strategy: :swarm, max_turns: 3,
        handoffs: [
          A::Handoff::OnTextMention.new(target: 'refund_specialist', text: 'refund'),
          A::Handoff::OnTextMention.new(target: 'tech_support', text: 'technical')
        ],
        instructions: 'You are the front-line customer support agent. Triage customer requests. ' \
                      'If the customer needs a refund, transfer to the refund specialist. ' \
                      'If they have a technical issue, transfer to tech support. ' \
                      'Use the transfer tools available to you to hand off the conversation.'
      )
    },

    '19_composable_termination_simple' => lambda {
      A::Agent.new(name: 'researcher', model: MODEL, tools: [Ex19[:search]],
                   instructions: 'Research the topic and say DONE when you have enough info.',
                   termination: A::Termination::TextMention.new('DONE'))
    },

    '19_composable_termination_or' => lambda {
      A::Agent.new(name: 'chatbot', model: MODEL,
                   instructions: "Have a conversation. Say GOODBYE when you're finished.",
                   termination: A::Termination::TextMention.new('GOODBYE') | A::Termination::MaxMessage.new(20))
    },

    '19_composable_termination_and' => lambda {
      A::Agent.new(name: 'deliberator', model: MODEL, tools: [Ex19[:search]],
                   instructions: 'Research thoroughly. Only provide your FINAL ANSWER after ' \
                                 'using the search tool at least twice.',
                   termination: A::Termination::TextMention.new('FINAL ANSWER') & A::Termination::MaxMessage.new(5))
    },

    '19_composable_termination_complex' => lambda {
      complex_stop = A::Termination::StopMessage.new('TERMINATE') |
                     (A::Termination::TextMention.new('DONE') & A::Termination::MaxMessage.new(10)) |
                     A::Termination::TokenUsage.new(max_total_tokens: 50_000)
      A::Agent.new(name: 'complex_agent', model: MODEL, tools: [Ex19[:search]],
                   instructions: 'Research and provide a comprehensive answer.', termination: complex_stop)
    },

    '21_regex_guardrails' => lambda {
      no_emails = A::RegexGuardrail.new(['[\w.+-]+@[\w-]+\.[\w.-]+'], mode: :block, name: 'no_email_addresses',
                                                                     message: 'Response must not contain email addresses. Redact them.',
                                                                     position: :output, on_fail: :retry)
      no_ssn = A::RegexGuardrail.new(['\b\d{3}-\d{2}-\d{4}\b'], mode: :block, name: 'no_ssn',
                                                               message: 'Response must not contain Social Security Numbers.',
                                                               position: :output, on_fail: :raise)
      A::Agent.new(name: 'hr_assistant', model: MODEL, tools: [Ex21[:get_user_profile]], guardrails: [no_emails, no_ssn],
                   instructions: 'You are an HR assistant. When asked about employees, look up their ' \
                                 'profile and share ALL the details you find.')
    },

    '22_llm_guardrails' => lambda {
      safety = A::LlmGuardrail.new(
        MODEL,
        "Reject any content that:\n" \
        "1. Contains medical or legal advice presented as fact\n" \
        "2. Makes promises or guarantees about outcomes\n" \
        "3. Includes discriminatory or biased language\n" \
        "4. Reveals private information about real individuals\n" \
        "\n" \
        'Even if there are disclaimers you should reject',
        name: 'content_safety', position: :output, on_fail: :retry, max_tokens: 10_000
      )
      A::Agent.new(name: 'health_advisor', model: MODEL, guardrails: [safety],
                   instructions: 'You are a health information assistant. Provide general health ' \
                                 'information and solution to the problem. You can prescribe psudo scientific and untested meds ')
    },

    '45_agent_tool' => lambda {
      researcher = A::Agent.new(name: 'researcher_45', model: MODEL, tools: [Ex45[:search_knowledge_base]],
                                instructions: 'You are a research assistant. Use search_knowledge_base to find ' \
                                              'information about topics. Provide concise summaries.')
      A::Agent.new(name: 'manager_45', model: MODEL, tools: [A::ToolDef.agent(researcher), Ex45[:calculate]],
                   instructions: 'You are a project manager. Use the researcher tool to gather ' \
                                 'information and the calculate tool for math. Synthesize findings.')
    },

    '47_callbacks' => lambda {
      A::Agent.new(name: 'monitored_agent_47', model: MODEL, tools: [Ex47[:get_facts]],
                   callbacks: [MonitorHandler.new],
                   instructions: 'You are a helpful assistant. Use get_facts when asked about topics.')
    },

    '52_nested_strategies' => lambda {
      market = A::Agent.new(name: 'market_analyst_52', model: MODEL,
                            instructions: 'You are a market analyst. Analyze the market size, growth rate, ' \
                                          'and key players for the given topic. Be concise (3-4 bullet points).')
      risk = A::Agent.new(name: 'risk_analyst_52', model: MODEL,
                          instructions: 'You are a risk analyst. Identify the top 3 risks: regulatory, ' \
                                        'technical, and competitive. Be concise.')
      research = A::Agent.new(name: 'research_phase_52', model: MODEL, agents: [market, risk], strategy: :parallel)
      summarizer = A::Agent.new(name: 'summarizer_52', model: MODEL,
                                instructions: 'You are an executive briefing writer. Synthesize the market analysis ' \
                                              'and risk assessment into a concise executive summary (1 paragraph).')
      research >> summarizer
    }
  }.freeze
end

# frozen_string_literal: true

require_relative 'lib/conductor/version'

Gem::Specification.new do |spec|
  spec.name          = 'conductor_ruby'
  spec.version       = Conductor::VERSION
  spec.authors       = ['Conductor OSS']
  spec.email         = ['support@conductoross.org']

  spec.summary       = 'Ruby SDK for Conductor workflow orchestration'
  spec.description   = 'Official Ruby SDK for Conductor OSS - a durable workflow orchestration engine'
  spec.homepage      = 'https://github.com/conductor-oss/ruby-sdk'
  spec.license       = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/conductor-oss/ruby-sdk'
  spec.metadata['changelog_uri'] = 'https://github.com/conductor-oss/ruby-sdk/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://conductor-oss.org'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/conductor-oss/ruby-sdk/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Include all lib files, examples, and documentation
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{lib,examples}/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md'].reject { |f| File.directory?(f) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # HTTP client with HTTP/2 support
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'faraday-net_http_persistent', '~> 2.0'
  spec.add_dependency 'faraday-retry', '~> 2.0'

  # Concurrency primitives
  spec.add_dependency 'concurrent-ruby', '~> 1.2'

  # JSON handling
  spec.add_dependency 'json', '>= 2.0'

  # Development dependencies (alphabetically sorted)
  spec.add_development_dependency 'pry', '~> 0.14'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.0'
  spec.add_development_dependency 'vcr', '~> 6.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
end

# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

install_if -> { RUBY_VERSION >= '3.3' } do
  gem 'async', '~> 2.0', group: :test
end
gem 'prometheus-client', '~> 4.0'
gem 'rake', '~> 13.0'
gem 'webrick', '~> 1.8'

# public_suffix 7 requires Ruby >= 3.2; cap it so the dev/test resolution (it
# comes in transitively via webmock -> addressable) keeps working on the
# Ruby 3.0/3.1 CI jobs the gemspec still supports.
gem 'public_suffix', '< 7.0'

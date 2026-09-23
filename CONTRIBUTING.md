# Contributing

Use Ruby 3.0+ and Bundler. From the repository root:

```bash
bundle install
bundle exec rspec spec/conductor/
bundle exec rubocop
bundle exec ruby -Ilib -rconductor -e 'puts Conductor::VERSION'
gem build conductor_ruby.gemspec
```

Add regression tests for fixes and tests for new behavior. Keep coverage at least
at its current level. Put unit tests in `spec/conductor/` and server tests in
`spec/integration/`. Update runnable examples when the public API changes.

For local OSS integration tests (requires Docker and Ruby):

```bash
scripts/run-integration-oss.sh
```

Add agent examples in `examples/agents/` and run them against Conductor with
LLM recording enabled:

```bash
bundle exec ruby -Ilib examples/agents/my_example.rb
```

Collect the recording JSON files and open a PR adding them to `llm-recordings/`
in [conductor-oss/conductor](https://github.com/conductor-oss/conductor).
Register the Ruby example in `examples/agents/catalog.rb` so CI replays it.

Without local Ruby, run unit tests and lint in Docker:

```bash
docker run --rm -v "$PWD":/app:z -w /app \
  -v ruby-sdk-bundle:/usr/local/bundle:z ruby:3.3 \
  bash -lc 'bundle install --quiet && bundle exec rspec spec/conductor/ && bundle exec rubocop'
```

The load harness runs with `bundle exec ruby harness/main.rb` using the same
server/auth environment variables as the SDK. It continuously starts workflows;
`HARNESS_WORKFLOWS_PER_SEC` defaults to 2. Kubernetes templates are in
[harness/manifests](harness/manifests/).

For releases, update `lib/conductor/version.rb` and `CHANGELOG.md`, then create a
GitHub release with a tag; CI publishes the gem.

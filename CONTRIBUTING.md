# Contributing to Conductor Ruby SDK

Thank you for your interest in contributing to the Conductor Ruby SDK! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We welcome contributors of all experience levels.

## Getting Started

### Prerequisites

- Ruby 2.6+ (Ruby 3.2+ recommended)
- Bundler
- Git

### Setup

1. Fork the repository on GitHub
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ruby-sdk.git
   cd ruby-sdk
   ```

3. Install dependencies:
   ```bash
   bundle install
   ```

4. Run tests to verify setup:
   ```bash
   bundle exec rspec spec/conductor/
   ```

## Development Workflow

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring

### Making Changes

1. Create a new branch:
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. Make your changes

3. Run tests:
   ```bash
   bundle exec rspec spec/conductor/
   ```

4. Run linting:
   ```bash
   bundle exec rubocop
   ```

5. Commit your changes:
   ```bash
   git commit -m "Add feature: description of changes"
   ```

6. Push to your fork:
   ```bash
   git push origin feature/my-new-feature
   ```

7. Create a Pull Request

## Testing

### Running Tests

```bash
# All unit tests
bundle exec rspec spec/conductor/

# Specific test file
bundle exec rspec spec/conductor/client/workflow_client_spec.rb

# With documentation format
bundle exec rspec spec/conductor/ --format documentation

# Integration tests (requires Conductor server)
CONDUCTOR_SERVER_URL=http://localhost:8080/api bundle exec rspec spec/integration/
```

### Writing Tests

- Place unit tests in `spec/conductor/`
- Place integration tests in `spec/integration/`
- Use descriptive test names
- Follow existing test patterns

Example test structure:
```ruby
RSpec.describe Conductor::Client::WorkflowClient do
  describe '#start' do
    context 'when workflow exists' do
      it 'returns a workflow ID' do
        # test implementation
      end
    end

    context 'when workflow does not exist' do
      it 'raises an ApiError' do
        # test implementation
      end
    end
  end
end
```

## Code Style

We use RuboCop for code style enforcement. Key guidelines:

- Use 2 spaces for indentation
- Use snake_case for methods and variables
- Use CamelCase for classes and modules
- Add documentation comments for public methods
- Keep methods small and focused

Run RuboCop to check your code:
```bash
bundle exec rubocop

# Auto-fix safe issues
bundle exec rubocop -a
```

## Documentation

- Update README.md for user-facing changes
- Add YARD documentation for new public methods
- Update CHANGELOG.md for notable changes
- Include examples for new features

### YARD Documentation Example

```ruby
# Starts a workflow execution
#
# @param name [String] The workflow name
# @param input [Hash] The workflow input (default: {})
# @param version [Integer, nil] The workflow version (optional)
# @return [String] The workflow ID
# @raise [ApiError] If the workflow doesn't exist
#
# @example Start a simple workflow
#   workflow_id = client.start('my_workflow', input: { key: 'value' })
#
def start(name, input: {}, version: nil)
  # implementation
end
```

## Pull Request Guidelines

### Before Submitting

- [ ] Tests pass locally
- [ ] RuboCop passes (or issues are intentional)
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated (if applicable)
- [ ] Commits are clean and well-described

### PR Description

Include:
- Summary of changes
- Motivation/context
- How to test
- Screenshots (if UI-related)

### Review Process

1. Automated CI checks run
2. Maintainers review code
3. Address feedback
4. Merge when approved

## Release Process

Releases are managed by maintainers:

1. Update version in `lib/conductor/version.rb`
2. Update CHANGELOG.md
3. Create GitHub release with tag
4. CI automatically publishes to RubyGems

## Project Structure

```
lib/
├── conductor.rb                    # Main entry point
├── conductor/
│   ├── version.rb                  # Version constant
│   ├── configuration.rb            # Configuration class
│   ├── exceptions.rb               # Exception classes
│   ├── client/                     # High-level clients
│   ├── http/
│   │   ├── api/                    # Resource API classes
│   │   ├── models/                 # Model classes
│   │   ├── api_client.rb           # HTTP client wrapper
│   │   └── rest_client.rb          # Faraday client
│   ├── orkes/                      # Orkes-specific code
│   ├── worker/                     # Worker framework
│   └── workflow/                   # Workflow DSL
```

## Getting Help

- Open an issue for bugs or feature requests
- Join [Conductor Slack](https://join.slack.com/t/orkes-conductor/shared_invite/zt-2vdbx239s-Eacdyqya9giNLHfrCavfaA)
- Check existing issues and PRs

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.

FROM ruby:3.3-alpine AS build
RUN apk add --no-cache build-base git
WORKDIR /package
COPY Gemfile Gemfile.lock conductor_ruby.gemspec ./
COPY lib/conductor/version.rb lib/conductor/version.rb
RUN bundle config set --local without 'development' \
 && bundle install --jobs 4

COPY lib/ lib/
COPY harness/ harness/

FROM ruby:3.3-alpine AS harness
RUN adduser -D -u 65532 nonroot
WORKDIR /app
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /package/lib /app/lib
COPY --from=build /package/harness /app/harness
USER nonroot
ENTRYPOINT ["ruby", "harness/main.rb"]

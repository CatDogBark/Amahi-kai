# Amahi Platform Makefile

# Development setup
setup:
	bin/dev-setup

# Start the development server
serve:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rails s -b 0.0.0.0

# Run all non-JS tests
test:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rspec --tag ~js

# Run all tests (requires chromium + chromedriver)
test-all:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rspec

# Run model specs only
test-models:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rspec spec/models/

# Precompile assets for production
assets:
	RAILS_ENV=production BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rails assets:precompile

# Database tasks
db-create:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rake db:create

db-migrate:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rake db:migrate

db-seed:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rake db:seed

db-reset:
	BUNDLE_APP_CONFIG=/tmp/.bundle bundle exec rake db:drop db:create db:migrate db:seed

# Cleanup
clean:
	rm -f log/development.log
	rm -f log/test.log
	rm -rf tmp/cache/*
	rm -rf tmp/lm*
	rm -rf tmp/server*
	rm -rf tmp/smb*
	rm -rf tmp/key*
	rm -rf tmp/capybara
	rm -rf coverage/

# Install dev dependencies (Ubuntu/Debian)
devel-deps:
	sudo apt-get install -y ruby ruby-dev build-essential \
		libmariadb-dev mariadb-client mariadb-server \
		libsqlite3-dev libxml2-dev libxslt-dev zlib1g-dev \
		libffi-dev libssl-dev libreadline-dev libyaml-dev \
		git curl unzip nodejs

.PHONY: setup serve test test-all test-models assets db-create db-migrate db-seed db-reset clean devel-deps

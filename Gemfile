source 'https://rubygems.org'

gem 'rake'
gem 'rails', '~> 7.0.0'

# Caching
gem 'dalli'
gem 'actionpack-action_caching'

# Configuration
gem 'yettings'

# Asset pipeline
gem 'sass-rails'
gem 'uglifier'

# UI
gem 'bootstrap', '~> 4.1.1'
gem 'popper_js', '~> 1.12.9'
gem 'jquery-rails'
gem 'jquery-ui-rails'
gem 'slim'
gem 'jbuilder'

# API
gem 'activeresource'

# Rails extensions
gem 'rails-observers'

# Authentication
gem 'scrypt'       # required by authlogic
gem 'authlogic'
gem 'bcrypt'

# Docker integration
gem 'docker-api'

# Ruby 2.7 compatibility pins
gem 'psych'  # needed for YAML alias support with yettings

group :development do
  gem 'listen'
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'puma'
  gem 'bullet'   # DB performance warnings
end

gem 'rspec-rails', group: [:test, :development]

group :test do
  gem 'factory_bot_rails'
  gem 'capybara'
  gem 'capybara-screenshot'
  gem 'database_cleaner'
  gem 'selenium-webdriver', '~> 4.9.0'
  gem 'simplecov', require: false
end

group :development, :production do
  gem 'mysql2'
end

group :development, :test do
  gem 'sqlite3', '~> 1.7.0'
end

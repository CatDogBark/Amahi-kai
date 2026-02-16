source 'https://rubygems.org'

gem 'rake'
gem 'rails', '~> 8.0.0'

gem 'dalli'
gem 'actionpack-action_caching'

gem 'sass-rails'
# gem 'propshaft'  # TODO: Replace sprockets with propshaft (requires full asset pipeline migration)
gem 'terser'

gem 'bootstrap', '~> 5.3'
gem 'jquery-rails'
gem 'jquery-ui-rails'
gem 'slim'
gem 'jbuilder'

gem 'activeresource'
gem 'rails-observers'

gem 'scrypt'
gem 'authlogic'
gem 'bcrypt'

gem 'docker-api'

gem 'rack', '~> 3.2.5'
gem 'rack-attack'

group :development do
  gem 'listen'
  gem 'better_errors'
  gem 'binding_of_caller', '~> 2.0'
  gem 'puma'
  gem 'bullet'
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
  gem 'sqlite3', '~> 2.0'
end

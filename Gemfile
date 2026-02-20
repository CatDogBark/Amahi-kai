source 'https://rubygems.org'

gem 'rake'
gem 'rails', '~> 8.0.0'

# gem 'dalli' # removed — no memcached
# gem 'actionpack-action_caching' # removed — unused

gem 'sass-rails'
# gem 'propshaft'  # TODO: Replace sprockets with propshaft (requires full asset pipeline migration)
gem 'terser'

gem 'bootstrap', '~> 5.3'
gem 'slim'
gem 'jbuilder'

# Modern Rails frontend
gem 'turbo-rails'
gem 'stimulus-rails'

gem 'activeresource'
# gem 'rails-observers' # removed — unused

gem 'scrypt'
gem 'authlogic'
gem 'bcrypt'

gem 'docker-api'
gem 'sys-filesystem'

gem 'rack', '~> 3.2.5'
gem 'rack-attack'

gem 'puma'

group :development do
  gem 'listen'
  gem 'better_errors'
  gem 'binding_of_caller', '~> 2.0'
  gem 'bullet'
end

gem 'rspec-rails', group: [:test, :development]

group :test do
  gem 'factory_bot_rails'
  gem 'capybara'
  # gem 'capybara-screenshot' # removed — no Selenium
  gem 'database_cleaner'
  # gem 'selenium-webdriver' # removed — no browser tests
  gem 'simplecov', require: false
end

group :development, :production do
  gem 'mysql2'
end

group :development, :test do
  gem 'sqlite3', '~> 2.0'
end

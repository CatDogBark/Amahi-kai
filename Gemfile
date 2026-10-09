source 'https://rubygems.org'

gem 'rails', '~> 8.1.0'
gem 'rake'

# Sprockets 4.2 passes json an option json 3 removed, so a production boot crashed as soon
# as compiled assets existed. 4.3 is the first release that works with json 3.
gem 'sprockets', '~> 4.3.0'
# The asset pipeline's Rails integration (helpers, assets:precompile). It used to come in
# with sass-rails; the stylesheets are plain CSS now.
gem 'sprockets-rails', '~> 3.5'
# gem 'propshaft'  # TODO: Replace sprockets with propshaft (requires full asset pipeline migration)
# gem 'terser' # JS minification — requires Node.js runtime, not worth the dependency

gem 'jbuilder'
gem 'slim'

# Stimulus is vendored (vendor/assets/javascripts/stimulus-iife.js), so it needs no gem.

gem 'bcrypt'

gem 'sys-filesystem'
# Folder downloads in the web file browser, streamed as the zip is made (FileBrowserController)
gem 'zip_kit', '~> 6.3', require: false

gem 'rack', '~> 3.2.5'
gem 'rack-attack'

gem 'puma'

group :development do
  gem 'better_errors'
  gem 'binding_of_caller', '~> 2.0'
  gem 'bullet'
  gem 'listen'
  # rubocop + brakeman installed directly in CI (not bundled)
end

gem 'rspec-rails', group: [:test, :development]

group :test do
  # Browser specs (spec/system): Capybara driving Chrome through its DevTools protocol
  gem 'capybara'
  gem 'cuprite'
  gem 'database_cleaner'
  gem 'factory_bot_rails'
  # Reads the folder zips in specs
  gem 'rubyzip', '~> 3.4', require: false
  gem 'simplecov', require: false
end

group :development, :production do
  gem 'mysql2'
end

group :development, :test do
  gem 'sqlite3', '~> 2.0'
end

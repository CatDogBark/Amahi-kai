source 'https://rubygems.org'

gem 'rake'
gem 'rails', '~> 8.1.0'

# gem 'dalli' # removed — no memcached
# gem 'actionpack-action_caching' # removed — unused

# Sprockets 4.2 passes json an option json 3 removed, so a production boot crashed as soon
# as compiled assets existed. 4.3 is the first release that works with json 3.
gem 'sprockets', '~> 4.3.0'
# The asset pipeline's Rails integration (helpers, assets:precompile). It used to come in
# with sass-rails; the stylesheets are plain CSS now.
gem 'sprockets-rails', '~> 3.5'
# gem 'propshaft'  # TODO: Replace sprockets with propshaft (requires full asset pipeline migration)
# gem 'terser' # JS minification — requires Node.js runtime, not worth the dependency

gem 'slim'
gem 'jbuilder'

# Stimulus controllers (app/assets/javascripts/controllers)
gem 'stimulus-rails'

# gem 'rails-observers' # removed — unused

gem 'bcrypt'

gem 'sys-filesystem'
# Folder downloads in the web file browser, streamed as the zip is made (FileBrowserController)
gem 'zip_kit', '~> 6.3', require: false

gem 'rack', '~> 3.2.5'
gem 'rack-attack'

gem 'puma'

group :development do
  gem 'listen'
  gem 'better_errors'
  gem 'binding_of_caller', '~> 2.0'
  gem 'bullet'
  # rubocop + brakeman installed directly in CI (not bundled)
end

gem 'rspec-rails', group: [:test, :development]

group :test do
  gem 'factory_bot_rails'
  gem 'database_cleaner'
  gem 'simplecov', require: false
  # Reads the folder zips in specs
  gem 'rubyzip', '~> 3.4', require: false
end

group :development, :production do
  gem 'mysql2'
end

group :development, :test do
  gem 'sqlite3', '~> 2.0'
end

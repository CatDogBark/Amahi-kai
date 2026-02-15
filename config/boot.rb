ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.

# Logger must be required before Rails 6.0 loads on Ruby 2.7
# to avoid NameError in ActiveSupport::LoggerThreadSafeLevel
require 'logger'

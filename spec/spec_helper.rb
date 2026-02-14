# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] ||= 'test'
require 'simplecov'
require 'simplecov_helper'
require File.expand_path("../../config/environment", __FILE__)
require 'rspec/rails'
require 'capybara/rspec'
require 'factory_bot_rails'

SCREENSHOTS_ON_FAILURES = false unless defined?(SCREENSHOTS_ON_FAILURES)

if SCREENSHOTS_ON_FAILURES
  require 'capybara-screenshot/rspec'
end

# Configure headless Chrome for JS specs
begin
  require 'selenium-webdriver'

  Capybara.register_driver :headless_chrome do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    options.add_argument('--window-size=1400,900')
    options.binary = '/usr/bin/chromium'
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
  end

  Capybara.javascript_driver = :headless_chrome
rescue LoadError
  # selenium-webdriver not available; JS specs will be skipped
end

# Required for using transactional fixtures with javascript driver
ActiveRecord::ConnectionAdapters::ConnectionPool.class_eval do
  def current_connection_id
    Thread.main.object_id
  end
end

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = false
  config.infer_base_class_for_anonymous_controllers = false
  config.order = "random"

  config.include FactoryBot::Syntax::Methods

  # Use rack_test by default (fast, no browser needed)
  config.before(:suite) do
    Capybara.default_driver = :rack_test
  end

  config.before(:each) do
    DatabaseCleaner.start
    # load the seed to get the minimum env going
    load "#{Rails.root}/db/seeds.rb"
  end

  config.after(:each) do
    DatabaseCleaner.clean
    Capybara.reset_sessions!
  end

  if SCREENSHOTS_ON_FAILURES
    Capybara::Screenshot.autosave_on_failure = true
  end
end

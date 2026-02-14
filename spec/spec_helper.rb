# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] ||= 'test'
require 'simplecov'
require 'simplecov_helper'
require File.expand_path("../../config/environment", __FILE__)
require 'rspec/rails'
require 'capybara/rspec'
require 'factory_bot_rails'

# turn this to true to get screenshots and html in tmp/capybara/*
SCREENSHOTS_ON_FAILURES = false unless defined?(SCREENSHOTS_ON_FAILURES)

if SCREENSHOTS_ON_FAILURES
  require 'capybara-screenshot/rspec'
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
  # Feature specs requiring JS will need a real browser driver (e.g. selenium + chromium)
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

# This is to stub with RSpec in FactoryBot

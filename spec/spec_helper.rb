# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] ||= 'test'
begin
  require 'simplecov'
  require_relative 'simplecov_helper'
rescue LoadError => e
  warn "SimpleCov not loaded: #{e.message}"
end
require File.expand_path("../../config/environment", __FILE__)
require 'rspec/rails'
require 'factory_bot_rails'

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = false
  config.infer_base_class_for_anonymous_controllers = false
  config.order = "random"

  config.include FactoryBot::Syntax::Methods

  config.before(:each) do |example|
    # Specs never run system commands or the root helper, even those that stub
    # Rails.env.production? to test production code; the few that test the real paths (with
    # the system calls stubbed) set Shell.simulated = false.
    Shell.simulated = true
    # Each example's data is rolled back after it. A browser spec's server thread has its own
    # connection, which can't see an open transaction, so those commit and are truncated.
    DatabaseCleaner[:active_record].strategy = example.metadata[:type] == :system ? :truncation : :transaction
    DatabaseCleaner.start
    # load the seed to get the minimum env going
    load "#{Rails.root}/db/seeds.rb"
    # Root helper calls recorded outside production (the seeds make some); start each example empty.
    Privileged.reset!
  end

  config.after(:each) do
    Shell.simulated = nil
    DatabaseCleaner.clean
  end
end

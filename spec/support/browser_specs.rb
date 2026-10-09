# Browser specs (docs/plans/browser-tests.md): Capybara drives Chrome, headless, through its
# DevTools protocol (Cuprite). The browser is Chrome or Chromium on the PATH, or BROWSER_PATH;
# without one the specs are skipped (CI's runners have Chrome; locally: apt install chromium).
#
# Every example fails on noise: anything the browser logs at error level (a script the
# Content-Security-Policy refused, a failed request, an exception) fails it, whatever it
# asserted. A page passes only when it loads clean.
require 'capybara/rspec'
require 'capybara/cuprite'

module BrowserSpec
  CANDIDATES = %w[google-chrome google-chrome-stable chromium chromium-browser chrome].freeze

  def self.browser_path
    @browser_path ||= ENV['BROWSER_PATH'].presence ||
                      CANDIDATES.map { |name| ENV['PATH'].split(':').map { |dir| File.join(dir, name) }.find { |f| File.executable?(f) } }.compact.first
  end

  # Browser log lines worth failing on. Error-level entries only; the water background's
  # WebGL notices and the like are warnings.
  def self.noise?(entry)
    entry[:level] == 'error'
  end

  module Helpers
    # Ferrum's page: where the DevTools session's commands and events live.
    def browser
      page.driver.browser.page
    end

    # Subscribes to the browser's console, exceptions and log (where Chrome reports a refused
    # inline script), collecting what it says for the example's check.
    def listen_to_browser
      @browser_log = []
      browser.command('Log.enable')
      browser.on('Log.entryAdded') do |params|
        entry = params['entry']
        @browser_log << { level: entry['level'], source: entry['source'], text: entry['text'], url: entry['url'] }
      end
      browser.on('Runtime.consoleAPICalled') do |params|
        text = Array(params['args']).map { |a| a['value'] || a['description'] }.join(' ')
        @browser_log << { level: params['type'], source: 'console', text: text }
      end
      browser.on('Runtime.exceptionThrown') do |params|
        detail = params['exceptionDetails']
        @browser_log << { level: 'error', source: 'exception', text: detail.dig('exception', 'description') || detail['text'] }
      end
    end

    def browser_errors
      (@browser_log || []).select { |entry| BrowserSpec.noise?(entry) }
    end

    # Signs in through the real form, as the seeded admin (db/seeds.rb runs before each example).
    def sign_in_as_admin
      Setting.set('setup_completed', 'true')
      visit '/login'
      fill_in 'username', with: User::SEED_ADMIN_LOGIN
      fill_in 'password', with: User::SEED_ADMIN_PASSWORD
      click_button I18n.t('log_in')
      expect(page).to have_css('.kai-mainnav')
    end
  end
end

# Passed through driven_by (Rails registers the driver itself, with these options).
CUPRITE_OPTIONS = {
  browser_path: BrowserSpec.browser_path,
  js_errors: true,
  process_timeout: 30,
  timeout: 15,
  browser_options: { 'force-prefers-reduced-motion' => nil, 'no-sandbox' => nil, 'disable-gpu' => nil }
}
Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }
Capybara.save_path = Rails.root.join('tmp/capybara')

RSpec.configure do |config|
  config.include BrowserSpec::Helpers, type: :system

  config.before(:each, type: :system) do
    skip 'no Chrome or Chromium found (set BROWSER_PATH, or apt install chromium)' unless BrowserSpec.browser_path
    driven_by :cuprite, screen_size: [1280, 800], options: CUPRITE_OPTIONS.dup
    listen_to_browser
  end

  config.after(:each, type: :system) do |example|
    next unless @browser_log
    errors = browser_errors
    if errors.any?
      report = errors.map { |e| "[#{e[:source]}] #{e[:text]}" }.join("\n")
      if example.exception
        example.exception.message << "\n\nThe browser also reported:\n#{report}"
      else
        raise "the browser reported errors on #{page.current_path}:\n#{report}"
      end
    end
  end
end

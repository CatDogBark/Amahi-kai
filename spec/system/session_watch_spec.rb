require 'rails_helper'

# A page whose sign-in ended goes to the sign-in page, and back to itself after it, instead of
# its buttons failing with "no answer from Amahi-kai" (session_watch.js).
RSpec.describe 'A page whose sign-in ended', type: :system do
  def sign_in_again
    fill_in 'username', with: User::SEED_ADMIN_LOGIN
    fill_in 'password', with: User::SEED_ADMIN_PASSWORD
    click_button I18n.t('log_in')
  end

  it 'goes to the sign-in page when a button finds the sign-in ended, and comes back after it' do
    sign_in_as_admin
    visit settings_system_status_path
    User.find_by(login: User::SEED_ADMIN_LOGIN).end_sessions! # Sign out, in another browser
    expect_browser_error(/status of 401/)
    find('#check-updates-btn').click
    expect(page).to have_field('username')
    sign_in_again
    expect(page).to have_current_path(settings_system_status_path)
  end

  it 'goes to the sign-in page by itself once its sign-in has run out' do
    sign_in_as_admin
    visit settings_system_status_path
    travel(UserSession::BROWSER_IDLE_TIMEOUT + 1.minute) do
      # Looked at again after hours away (the page's own clock moved on too, past its 30-second wait)
      page.execute_script('var now = Date.now; Date.now = function() { return now() + 3600000; };')
      expect_browser_error(/status of 401/) # the update dialog's own refresh, when the tab is looked at, may tell it first
      page.execute_script("document.dispatchEvent(new Event('visibilitychange'))")
      expect(page).to have_field('username')
    end
  end

  it 'reloads a page from an earlier sign-in, saying so' do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in_as_admin
    visit settings_system_status_path
    page.execute_script(%(document.querySelector('meta[name="csrf-token"]').content = 'from-an-earlier-sign-in'))
    expect_browser_error(/status of 422/)
    find('#check-updates-btn').click
    expect(page).to have_css('.amahi-toast', text: 'This page was out of date, so it was reloaded')
    expect(page).to have_current_path(settings_system_status_path)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end

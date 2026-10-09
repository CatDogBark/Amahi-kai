require 'rails_helper'

# In a real browser: the sign-in page, then the dashboard, with every script running and
# nothing refused or thrown (spec/system/support/browser.rb fails the example otherwise).
RSpec.describe 'Sign in and the dashboard', type: :system do
  it "signs in through the form, with the username field focused" do
    Setting.set('setup_completed', 'true')
    visit '/login'
    expect(page.evaluate_script('document.activeElement && document.activeElement.id')).to eq('username')
    fill_in 'username', with: User::SEED_ADMIN_LOGIN
    fill_in 'password', with: User::SEED_ADMIN_PASSWORD
    click_button I18n.t('log_in')
    expect(page).to have_css('.kai-mainnav .kai-navlink[aria-current="page"]', text: 'Dashboard')
    expect(page).to have_css('#toast-container .amahi-toast', text: 'Logged in successfully')
  end

  it "shows the dashboard with its water background running, and the wrench toggles Advanced mode" do
    sign_in_as_admin
    expect(page).to have_text('Welcome to Amahi-kai')
    # The water background is a canvas the ocean script draws on
    expect(page).to have_css('canvas', visible: :all)
    expect(page.evaluate_script("document.querySelector('canvas') && document.querySelector('canvas').width")).to be > 0

    toggle = find('#advanced-toggle')
    before = toggle['aria-pressed']
    toggle.click
    expect(page).to have_css("#advanced-toggle[aria-pressed='#{before == 'true' ? 'false' : 'true'}']")
    expect(Setting.get('advanced')).to eq(before == 'true' ? '0' : '1')
  end

  it "fits the header in a medium-width window: the name on one line, the tools inside it" do
    sign_in_as_admin
    page.driver.resize(860, 800)
    header = page.evaluate_script(<<~JS)
      (() => {
        const box = s => document.querySelector(s).getBoundingClientRect();
        return { brand: box('.kai-brand').height, tools: box('.kai-header-tools').right, search: box('#searchform').top, nav: box('.kai-mainnav').bottom };
      })()
    JS
    expect(header['brand']).to be < 40
    expect(header['tools']).to be <= 860
    expect(header['search']).to be >= header['nav'] # its own row, below the sections
  end

  it "hears what the browser logs (the harness fails an example on an error; this one clears it)" do
    sign_in_as_admin
    page.execute_script("console.error('a test error'); console.log('a test note')")
    expect(browser_errors.map { |e| e[:text] }).to eq(['a test error'])
    @browser_log.clear
  end
end

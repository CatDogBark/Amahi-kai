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

  # Real time is the clock itself: a faster speed tried and turned off leaves no offset behind
  it "keeps the water's clock on the real one after a faster speed is turned off" do
    sign_in_as_admin
    find('.ocean-toggle').click
    within('.ocean-panel') do
      click_button 'Day in 2 min'
      sleep 2 # 24 minutes of the scene's day
      click_button 'Real time'
    end
    minutes = ->(hhmm) { h, m = hhmm.split(':').map(&:to_i); (h * 60) + m }
    shown = minutes.call(find('[data-ocean-time]').text[/\d\d:\d\d/])
    clock = minutes.call(page.evaluate_script(
                           "(() => { const d = new Date(); return d.getHours() + ':' + d.getMinutes(); })()"
                         ))
    expect([(shown - clock) % 1440, (clock - shown) % 1440].min).to be <= 1
  end

  it 'signs out from the header, and from its menu on a phone' do
    sign_in_as_admin
    find("button[aria-label='Sign out #{User::SEED_ADMIN_LOGIN}']").click
    expect(page).to have_field('username')

    sign_in_as_admin
    page.driver.resize(400, 800)
    find('.navbar-toggler').click
    within('#amahi-nav') { click_button "Sign out #{User::SEED_ADMIN_LOGIN}" }
    expect(page).to have_field('username')
  ensure
    page.driver.resize(1280, 800)
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
    # The browser sends what it logs on its own time: wait for it rather than read the log at once.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.05 while browser_errors.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    expect(browser_errors.map { |e| e[:text] }).to eq(['a test error'])
    @browser_log.clear
  end
end

require 'rails_helper'

# The layout: dark for everyone, the header's sections, the page heading and Setup's tabs.
RSpec.describe 'The layout', type: :request do
  def page_at(path)
    get path
    Nokogiri::HTML(response.body)
  end

  it 'is dark for everyone, with no theme switcher, the sign-in page too' do
    get '/login'
    expect(Nokogiri::HTML(response.body).at('html')['data-theme']).to eq('dark')
    login_as_admin
    page = page_at('/shares')
    expect(page.at('html')['data-theme']).to eq('dark')
    expect(page.at('html')['data-bs-theme']).to eq('dark')
    expect(response.body).not_to include('theme-switcher', 'setTheme', "localStorage.getItem('theme')")
  end

  it "has Dashboard, Files, Apps and Setup for admins, marking the page's section, and the water background's button" do
    login_as_admin
    nav = ->(page) { page.css('.kai-mainnav .kai-navlink').to_h { |a| [a.text.strip, a['aria-current']] } }
    expect(nav.call(page_at('/'))).to eq('Dashboard' => 'page', 'Files' => nil, 'Apps' => nil, 'Setup' => nil)
    expect(nav.call(page_at('/files'))).to include('Files' => 'page')
    expect(nav.call(page_at('/shares'))).to include('Setup' => 'page')
    expect(nav.call(page_at('/apps'))).to include('Apps' => 'page', 'Setup' => nil)
    page = page_at('/shares')
    expect(page.at_css('.kai-header [data-ocean-panel]')['aria-label']).to eq('Water background')
    expect(page.at_css('#update-btn')).to be_present
    expect(page.at_css('.kai-brand').text.strip).to eq('Amahi-kai')
  end

  it "shows Advanced mode's toggle as pressed when the setting is on, reading the setting once per page" do
    login_as_admin
    { '1' => 'true', '0' => 'false' }.each do |value, pressed|
      Setting.set('advanced', value)
      queries = []
      counter = lambda do |*, payload|
        values = Array(payload[:type_casted_binds]).flatten.map(&:to_s)
        queries << payload[:sql] if payload[:sql].to_s.include?('settings') && (values.include?('advanced') || payload[:sql].include?("'advanced'"))
      end
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        get '/shares'
      end
      expect(Nokogiri::HTML(response.body).at_css('#advanced-toggle')['aria-pressed']).to eq(pressed)
      expect(queries.size).to eq(1), queries.inspect
    end
    Setting.where(name: 'advanced').delete_all
    get '/shares'
    expect(Nokogiri::HTML(response.body).at_css('#advanced-toggle')['aria-pressed']).to eq('false')
  end

  it "labels Apps' sub-tabs Available and Installed" do
    login_as_admin
    expect(page_at('/apps').css('.setup-subtab a').map { |a| a.text.strip }).to eq(%w[Available Installed])
  end

  it 'gives a user Dashboard and Files only' do
    login_as(create(:user))
    page = page_at('/files')
    expect(page.css('.kai-mainnav .kai-navlink').map { |a| a.text.strip }).to eq(%w[Dashboard Files])
    expect(page.at_css('#update-btn')).to be_nil
  end

  it "titles the page under its section, with Setup's tabs (icons and all) only on Setup's pages" do
    login_as_admin
    share = create(:share, name: 'Test', path: Dir.mktmpdir)
    page = page_at('/shares')
    expect(page.at_css('.kai-eyebrow').text).to eq('Setup')
    expect(page.at_css('.kai-page-title').text).to eq('Shares')
    tabs = page.css('ul.setup-main-tab .nav-link')
    expect(tabs.map { |a| a.text.strip }).to include('Users', 'Shares', 'Disks')
    expect(tabs.find { |a| a['aria-current'] == 'page' }.text.strip).to eq('Shares')
    expect(tabs.first.at_css('svg')).to be_present

    page = page_at('/files')
    expect(page.at_css('.kai-eyebrow').text).to eq('Files')
    expect(page.at_css('.kai-page-title').text).to eq('Shares')
    # Inside a share and on the Trash, the breadcrumbs are the heading (Shares › ...), still under Files
    { "/files/#{share.name}/browse" => 'Test', '/files/trash' => 'Trash' }.each do |path, title|
      page = page_at(path)
      expect(page.at_css('.kai-eyebrow').text).to eq('Files'), path
      expect(page.at_css('.kai-page-title')).to be_nil, path
      expect(page.at_css('.fb-breadcrumbs').text.squish).to eq("Shares #{title}"), path
      expect(page.at_css('title').text).to eq("Amahi-kai › #{title}"), path
    end
    %W[/files /files/#{share.name}/browse /files/trash].each { |path| expect(page_at(path).at_css('ul.setup-main-tab')).to be_nil, path }
  ensure
    FileUtils.rm_rf(share.path) if share
  end
end

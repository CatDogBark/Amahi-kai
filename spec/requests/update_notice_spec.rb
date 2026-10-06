require 'rails_helper'

# The header's update button opens the System Update dialog (layouts/_system_update) on every
# page; a dot on it and a line on the dashboard say when an update is waiting.
RSpec.describe 'Update notice', type: :request do
  def update_status(data)
    allow(UpdateStatus).to receive(:load).and_return(UpdateStatus.new(data))
  end

  def page
    Nokogiri::HTML(response.body)
  end

  let(:available) do
    { 'checked_at' => 1.hour.ago.utc.iso8601, 'current' => 'aaaaaaa1', 'latest' => 'bbbbbbb2',
      'available' => true, 'behind' => 2,
      'commits' => [{ 'sha' => 'bbbbbbb', 'subject' => 'Update notice (#43)' },
                    { 'sha' => 'ccccccc', 'subject' => 'Storage plan (#42)' }],
      'changelog' => ['**The header says when an update is waiting.** It reads `update-status.json`.',
                      '<script>alert(1)</script> stays text'] }
  end

  let(:up_to_date) do
    { 'checked_at' => 5.minutes.ago.utc.iso8601, 'current' => 'aaaaaaa1', 'latest' => 'aaaaaaa1',
      'available' => false, 'behind' => 0 }
  end

  context 'as an admin, with an app update waiting and Amahi-kai up to date' do
    before do
      login_as_admin
      update_status(up_to_date)
      entry = AppCatalog.find('gitea')
      DockerApp.create!(identifier: 'gitea', name: 'Gitea', status: 'running',
                        image: "#{entry[:image].split(/[:@]/).first}:1.0.0-rootless@sha256:#{'a' * 64}")
      get root_path
    end

    it 'puts the dot on the update button, and the dialog lists the app, to update from the Apps page' do
      button = page.at_css('#update-btn')
      expect(button['data-tip']).to eq('Update available: 1 app update')
      expect(button.at_css('.update-dot')).not_to be_nil
      dialog = page.at_css('#whats-new')
      expect(dialog.at_css('.modal-title').text).to include("What's new")
      expect(dialog.at_css('.whats-new-apps').text).to include('An app update', "Gitea 1.0.0-rootless → #{AppCatalog.tag(entry_image)}")
      expect(dialog.at_css('.whats-new-apps a[href="/apps/installed_apps"]')).not_to be_nil
      expect(dialog.text).to include('Up to date (aaaaaaa)', 'checks itself and its apps every 6 hours')
      expect(dialog.at_css('#whats-new-install')).to be_nil # Update now is Amahi-kai's
      expect(dialog.at_css('#whats-new-check')).not_to be_nil
    end

    def entry_image
      AppCatalog.find('gitea')[:image]
    end
  end

  context 'as an admin, with an update waiting' do
    before do
      login_as_admin
      update_status(available)
      get root_path
    end

    it 'puts a dot on the update button, which opens the dialog instead of updating' do
      button = page.at_css('#update-btn')
      expect(button['data-tip']).to eq('Update available: 2 changes')
      expect(button.at_css('.update-dot')).not_to be_nil
      expect(button.key?('data-whats-new')).to be(true)
      expect(button['onclick']).to be_nil
    end

    it "says so on the dashboard" do
      notice = page.at_css('.update-notice')
      expect(notice.text).to include("Update available: 2 changes — see what's new")
      expect(notice.key?('data-whats-new')).to be(true)
    end

    it "shows what's new: the changelog entries, the pull requests, and Update now" do
      dialog = page.at_css('#whats-new')
      expect(dialog.at_css('.modal-title').text).to include("What's new")
      expect(dialog.text).to include('2 changes ready to install (aaaaaaa → bbbbbbb)')
      entry = dialog.css('.whats-new-changelog li').first
      expect(entry.at_css('strong').text).to eq('The header says when an update is waiting.')
      expect(entry.at_css('code').text).to eq('update-status.json')
      expect(dialog.at_css('.whats-new-changelog script')).to be_nil
      expect(dialog.css('.whats-new-changelog li').last.text).to eq('<script>alert(1)</script> stays text')
      expect(dialog.at_css('a[href="https://github.com/CatDogBark/Amahi-kai/pull/43"]')).not_to be_nil
      install = dialog.at_css('#whats-new-install')
      expect(install['data-url']).to eq('/settings/update_system')
      expect(dialog.at_css('#whats-new-repair')).to be_nil
    end

    it 'keeps the System Update window on the page' do
      expect(page.at_css('#system-update-install-modal')).not_to be_nil
    end
  end

  context 'as an admin, up to date' do
    before do
      login_as_admin
      update_status(up_to_date)
      get root_path
    end

    it 'shows no dot and no dashboard notice' do
      expect(page.at_css('#update-btn')['data-tip']).to eq('System Update')
      expect(page.at_css('.update-dot')).to be_nil
      expect(page.at_css('.update-notice')).to be_nil
    end

    it 'offers Check now and Repair instead of Update now' do
      dialog = page.at_css('#whats-new')
      expect(dialog.text).to include('Up to date (aaaaaaa).', 'Checked 5 minutes ago')
      expect(dialog.at_css('#whats-new-check')['data-url']).to eq('/settings/check_updates')
      expect(dialog.at_css('#whats-new-repair')['data-url']).to eq('/settings/update_system?repair=1')
      expect(dialog.at_css('#whats-new-install')).to be_nil
    end
  end

  it 'is on the debug pages too' do
    login_as_admin
    update_status(available)
    get '/tab/debug'
    expect(page.at_css('#update-btn .update-dot')).not_to be_nil
    expect(page.at_css('#whats-new #whats-new-install')).not_to be_nil
  end

  it "isn't shown to users who aren't admins" do
    ensure_setup_completed!
    login_as(create(:user))
    update_status(available)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(page.at_css('#update-btn')).to be_nil
    expect(page.at_css('#whats-new')).to be_nil
    expect(page.at_css('.update-notice')).to be_nil
  end
end

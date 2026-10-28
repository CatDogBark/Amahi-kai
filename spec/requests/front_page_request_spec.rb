require 'spec_helper'

describe "Front page", type: :request do
  describe "unauthenticated access" do
    it "redirects to login page by default" do
      get root_path
      expect(response).to redirect_to(new_user_session_url)
    end

    it "always redirects to login when not authenticated" do
      get root_path
      expect(response).to redirect_to(new_user_session_url)
    end
  end

  describe "authenticated access" do
    before { login_as_admin }

    it "shows dashboard after login" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end

    it "shows logout link" do
      get root_path
      expect(response.body).to include("Sign out")
    end
  end

  describe "security updates waiting" do
    let(:overdue) { [{ package: 'libssl3t64', available: '3.0', since: Time.zone.parse('2026-10-02') }, { package: 'samba', available: '1.1', since: 3.days.ago }] }

    it "tells admins, linking to System Dependencies" do
      allow(SystemDependencies).to receive(:overdue_security_updates).and_return(overdue)
      login_as_admin
      get root_path
      notice = Nokogiri::HTML(response.body).at_css('#security-updates-notice a')
      expect(notice['href']).to eq('/settings/dependencies')
      expect(notice.text.squish).to include('2 security updates waiting since October 2, 2026')
    end

    it "says nothing when none has waited, and nothing to other users" do
      allow(SystemDependencies).to receive(:overdue_security_updates).and_return([])
      login_as_admin
      get root_path
      expect(response.body).not_to include('security-updates-notice')
      allow(SystemDependencies).to receive(:overdue_security_updates).and_return(overdue)
      login_as(create(:user))
      get root_path
      expect(response.body).not_to include('security-updates-notice')
    end
  end

  describe "app updates" do
    # An app installed from an older image than the catalog's: System Update brought a newer one.
    def installed(identifier, tag: 'old', **attrs)
      entry = AppCatalog.find(identifier)
      DockerApp.create!({ identifier: identifier, name: entry[:name], status: 'running',
                          image: "#{entry[:image].split(/[:@]/).first}:#{tag}@sha256:#{'a' * 64}" }.merge(attrs))
    end

    it "tells admins which apps have an update, with their versions" do
      login_as_admin
      installed('gitea', tag: '1.0.0-rootless')
      installed('jellyfin', image: AppCatalog.find('jellyfin')[:image]) # up to date
      get root_path
      expect(response.body).to include(
        "App update: Gitea 1.0.0-rootless → #{AppCatalog.tag(AppCatalog.find('gitea')[:image])} — update on the Apps page"
      )
      expect(response.body).to include('href="/apps" class="update-notice"', '1 update')
      expect(response.body).not_to include('Jellyfin 10')
    end

    it "names three and counts the rest" do
      login_as_admin
      %w[bittube gitea jellyfin transmission].each { |id| installed(id) }
      get root_path
      notice = Nokogiri::HTML(response.body).at_css('a.update-notice[href="/apps"]').text
      expect(notice).to include('App updates:', 'bitTube old →', ' · Gitea old →', ' · Jellyfin old →', 'and 1 more')
      expect(notice).not_to include('Transmission old') # the System Update dialog lists all four
      expect(response.body).to include('4 updates')
    end

    it "says nothing when every app is up to date, or to users who can't update them" do
      login_as_admin
      get root_path
      expect(response.body).not_to include('App update')

      installed('gitea')
      login_as(create(:user, admin: false))
      get root_path
      expect(response.body).not_to include('App update', '1 update')
    end
  end

  describe "the Storage card" do
    let(:pool) do
      drives = %w[b c d e].map { |n| { 'name' => "/dev/disk/by-id/ata-Samsung_SSD_870_S#{n}-part1", 'device' => "/dev/sd#{n}1", 'state' => 'ONLINE', 'children' => [] } }
      { 'name' => 'data', 'health' => 'ONLINE', 'managed' => true, 'used' => 1_500_000_000_000, 'available' => 1_300_000_000_000,
        'mountpoint' => '/srv/pools/data', 'vdevs' => [{ 'name' => 'raidz1-0', 'state' => 'ONLINE', 'children' => drives }] }
    end
    let(:greyhole) do
      { active: true, drives: 2, total: 2_000_000_000_000, used: 1_900_000_000_000, free: 100_000_000_000, percent: 95.0,
        copies: 2, effective_capacity: 1_000_000_000_000, pending: 1 }
    end

    def card
      Nokogiri::HTML(response.body).at_css('#storage-card')
    end

    def health(*pools)
      allow(StorageHealth).to receive(:load).and_return(StorageHealth.new('pools' => pools))
    end

    it "shows each of Amahi-kai's ZFS pools with its kind, health and usable space, linking admins to it" do
      health(pool, pool.merge('name' => 'rpool', 'managed' => false))
      login_as_admin
      get root_path
      row = card.at_css('#storage-pool-zfs-data')
      expect(row.text.squish).to eq('data ZFS RAIDZ1 · 4 drives ONLINE Manage → 1.36 TB used of 2.55 TB (1.18 TB free) 53.6%')
      expect(row.at_css('.badge')['class']).to include('bg-success')
      expect(row.at_css('a')['href']).to eq('/disks/pools')
      expect(row.at_css('.progress-bar')['style']).to eq('width: 53.6%')
      expect(card.css('.storage-pool').size).to eq(1) # not the system's own pool
    end

    it "shows a pool that isn't healthy as ZFS says, and one the check couldn't read without its space" do
      health(pool.merge('health' => 'DEGRADED'), { 'name' => 'tank', 'health' => 'FAULTED', 'managed' => true, 'error' => 'cannot open' })
      login_as_admin
      get root_path
      expect(card.at_css('#storage-pool-zfs-data .badge').text).to eq('DEGRADED')
      expect(card.at_css('#storage-pool-zfs-tank').text.squish).to eq("tank ZFS FAULTED Manage → Its space couldn't be read at the last check.")
    end

    it "shows the Greyhole pool while Greyhole runs, after the ZFS pools" do
      health(pool)
      allow(DashboardStats).to receive(:pool_status).and_return(greyhole)
      login_as_admin
      get root_path
      expect(card.css('.storage-pool').map { |row| row['id'] }).to eq(%w[storage-pool-zfs-data storage-pool-greyhole])
      row = card.at_css('#storage-pool-greyhole')
      expect(row.text.squish).to eq('Greyhole 2 drives · up to 2 copies Manage → 1.73 TB used of 1.82 TB (93.1 GB free) 95.0% ~931 GB effective 1 pending operation')
      expect(row.at_css('a')['href']).to eq('/disks/storage_pool')
      expect(row.at_css('.progress-bar')['class']).to include('bg-danger')
    end

    it "shows users who aren't admins the pools, without the links to manage them" do
      health(pool)
      allow(DashboardStats).to receive(:pool_status).and_return(greyhole)
      login_as(create(:user))
      get root_path
      expect(card.css('.storage-pool').size).to eq(2)
      expect(card.css('a')).to be_empty
    end

    it "isn't there without a pool" do
      health(pool.merge('managed' => false))
      login_as_admin
      get root_path
      expect(response).to have_http_status(:ok)
      expect(card).to be_nil
    end
  end

  describe "login flow" do
    it "logs in with valid credentials and shows dashboard" do
      ensure_setup_completed!
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "secretpassword" }
      expect(response).to redirect_to(root_url)
      follow_redirect!
      expect(response.body).to include("Dashboard")
    end

    it "rejects bad username" do
      user = create(:user)
      post user_sessions_path, params: { username: "bogus", password: "secretpassword" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Incorrect username or password")
    end

    it "rejects bad password" do
      user = create(:user)
      post user_sessions_path, params: { username: user.login, password: "bogus" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Incorrect username or password")
    end

    it "logs out and redirects to root" do
      user = create(:user)
      login_as(user)
      delete user_session_path(0)
      expect(response).to redirect_to(root_path)
    end
  end
end

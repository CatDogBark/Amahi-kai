require 'spec_helper'

# The Apps pages (docs/plans/apps.md, P4.1): the catalog's apps, installed through the root
# helper. Outside production Privileged.call records each call instead of running it.
describe "Docker Apps", type: :request do
  before do
    login_as_admin
    allow(DockerService).to receive(:installed?).and_return(true)
    allow(DockerService).to receive(:running?).and_return(true)
  end

  def gitea(attrs = {})
    DockerApp.create!({ identifier: 'gitea', name: 'Gitea', image: 'gitea/gitea:1.27.3-rootless', status: 'running',
                        host_port: 3300 }.merge(attrs))
  end

  def helper_fails(operation, message)
    allow(Privileged).to receive(:call).and_call_original
    allow(Privileged).to receive(:call).with(operation, any_args).and_raise(Privileged::Error.new(operation, message))
  end

  describe "the catalog page" do
    it "lists the five apps, with Install for the ones not installed" do
      get "/apps/docker_apps"
      expect(response).to have_http_status(:ok)
      %w[Jellyfin Vaultwarden Gitea Transmission].each { |name| expect(response.body).to include(name) }
      expect(CGI.unescapeHTML(response.body))
        .to include(%(openAppInstall('uptimekuma', '/apps/docker/install_stream/uptimekuma', "Uptime Kuma")))
    end

    it "asks Docker for the apps' states, and links a running app to its own port" do
      gitea
      get "/apps/docker_apps", headers: { 'Host' => '192.168.1.111' }
      expect(Privileged.calls).to include(['apps.status', {}])
      expect(response.body).to include('href="http://192.168.1.111:3300/"')
      expect(response.body).not_to include('/app/gitea')
      expect(response.body).to include("Its data stays in #{AppCatalog.apps_root}/gitea")
    end

    it "filters by category" do
      get "/apps/docker_apps", params: { category: "media" }
      expect(response.body).to include("Jellyfin")
      expect(response.body).not_to include("Vaultwarden")
    end

    it "offers to delete the data an earlier install kept" do
      allow(AppCatalog).to receive(:data_kept?).and_return(false)
      allow(AppCatalog).to receive(:data_kept?).with('gitea').and_return(true)
      get "/apps/docker_apps"
      expect(response.body).to include("/apps/docker/uninstall/gitea?delete_data=1")
      expect(response.body.scan("delete_data=1").size).to eq(1)
    end

    it "shows an installed app's generated passwords to admins, with a copy button" do
      gitea(identifier: 'transmission', name: 'Transmission', host_port: 9091)
      allow(AppCatalog).to receive(:secrets).and_return([])
      allow(AppCatalog).to receive(:secrets).with('transmission')
                                            .and_return([{ label: 'Web interface password (user admin)', value: 'pa55word' }])
      get "/apps/installed_apps"
      expect(response.body).to include('Web interface password (user admin)')
      expect(response.body).to include('data-copy="pa55word"')
    end

    it "shows Docker as not installed when checking it fails" do
      allow(DockerService).to receive(:installed?).and_raise(RuntimeError, "docker not found")
      get "/apps/docker_apps"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Install Docker')
    end
  end

  describe "installing" do
    it "installs through the helper, streaming its progress, and says where to open the app" do
      get "/apps/docker/install_stream/uptimekuma", headers: same_origin.merge('Host' => '192.168.1.111')
      expect(Privileged.calls).to include(['apps.install', { app: 'uptimekuma' }])
      expect(response.body).to include('✓ Uptime Kuma is installed and running')
      expect(response.body).to include('Open it at http://192.168.1.111:3001/')
      expect(DockerApp.find_by(identifier: 'uptimekuma')).to have_attributes(status: 'running', host_port: 3001,
                                                                             container_name: 'amahi-uptimekuma')
    end

    it "records and shows the helper's reason when it fails" do
      helper_fails('apps.install', 'docker exited 1: pull access denied')
      get "/apps/docker/install_stream/uptimekuma", headers: same_origin
      expect(response.body).to include('✗ docker exited 1: pull access denied')
      expect(DockerApp.find_by(identifier: 'uptimekuma')).to have_attributes(status: 'error', error_message: 'docker exited 1: pull access denied')
    end

    it "refuses an app that isn't in the catalog" do
      get "/apps/docker/install_stream/portainer", headers: same_origin
      expect(response.body).to include("That app isn't in the catalog")
      expect(Privileged.calls.map(&:first)).not_to include('apps.install')
    end
  end

  describe "start, stop and restart" do
    it "goes through the helper and answers ok" do
      gitea(status: 'stopped')
      post "/apps/docker/start/gitea"
      expect(response.parsed_body).to eq('status' => 'ok')
      post "/apps/docker/stop/gitea"
      post "/apps/docker/restart/gitea"
      expect(Privileged.calls.map(&:first)).to eq(%w[apps.start apps.stop apps.restart])
      expect(DockerApp.find_by(identifier: 'gitea').status).to eq('running')
    end

    it "answers with the helper's reason, or that the app isn't installed" do
      gitea
      helper_fails('apps.stop', 'docker exited 1: is the docker daemon running?')
      post "/apps/docker/stop/gitea"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['message']).to eq('docker exited 1: is the docker daemon running?')
      post "/apps/docker/start/jellyfin"
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['message']).to eq("That app isn't installed")
    end
  end

  describe "uninstalling" do
    it "keeps the data unless asked to delete it" do
      gitea
      post "/apps/docker/uninstall/gitea"
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(DockerApp.find_by(identifier: 'gitea')).to be_nil
      post "/apps/docker/uninstall/gitea", params: { delete_data: '1' }
      expect(Privileged.calls).to eq([['apps.uninstall', { app: 'gitea', delete_data: false }],
                                      ['apps.uninstall', { app: 'gitea', delete_data: true }]])
    end

    it "refuses an app that isn't in the catalog" do
      post "/apps/docker/uninstall/portainer"
      expect(response).to have_http_status(:not_found)
      expect(Privileged.calls).to be_empty
    end
  end

  describe "the dashboard" do
    it "links each running app to its own port" do
      gitea(show_in_dashboard: true)
      get "/", headers: { 'Host' => '192.168.1.111' }
      expect(response.body).to include('href="http://192.168.1.111:3300/"')
    end
  end

  it "reports an app's status as JSON" do
    gitea
    get "/apps/docker/status/gitea"
    expect(response.parsed_body).to include('status' => 'running', 'host_port' => 3300)
    get "/apps/docker/status/jellyfin"
    expect(response.parsed_body).to eq('status' => 'available')
  end
end

require 'spec_helper'

# An installed app's record. The root helper does the work (apps.*); outside production
# Privileged.call records the calls instead of running them.
describe DockerApp do
  def build_app(attrs = {})
    DockerApp.new({ identifier: 'gitea', name: 'Gitea', image: 'gitea/gitea:1.27.3-rootless', status: 'running',
                    host_port: 3300 }.merge(attrs))
  end

  def helper_fails(operation, message)
    allow(Privileged).to receive(:call).and_call_original
    allow(Privileged).to receive(:call).with(operation, any_args).and_raise(Privileged::Error.new(operation, message))
  end

  describe 'validations' do
    it 'requires an identifier, a name and an image' do
      expect(build_app(identifier: nil)).not_to be_valid
      expect(build_app(name: nil)).not_to be_valid
      expect(build_app(image: nil)).not_to be_valid
    end

    it 'accepts only known statuses' do
      expect(build_app(status: 'invalid')).not_to be_valid
      %w[available pulling installing running stopped error].each do |status|
        expect(build_app(status: status)).to be_valid
      end
    end

    it 'enforces a unique identifier' do
      build_app.save!
      expect(build_app(name: 'Other')).not_to be_valid
    end
  end

  describe 'scopes' do
    before do
      build_app(identifier: 'app1', status: 'running').save!
      build_app(identifier: 'app2', status: 'stopped').save!
      build_app(identifier: 'app3', status: 'running', category: 'media').save!
    end

    it 'finds running apps and apps by category' do
      expect(DockerApp.running.count).to eq(2)
      expect(DockerApp.by_category('media').count).to eq(1)
    end
  end

  describe '#url' do
    it "is the app's own port on the address the page was reached at" do
      expect(build_app.url('192.168.1.111')).to eq('http://192.168.1.111:3300/')
      expect(build_app(host_port: nil).url('192.168.1.111')).to be_nil
    end
  end

  describe 'start, stop and restart' do
    let(:app) { build_app(status: 'stopped').tap(&:save!) }

    it 'goes through the helper, naming only the app' do
      app.start!
      expect(app.reload.status).to eq('running')
      app.stop!
      expect(app.reload.status).to eq('stopped')
      app.restart!
      expect(app.reload.status).to eq('running')
      expect(Privileged.calls).to eq([['apps.start', { app: 'gitea' }], ['apps.stop', { app: 'gitea' }],
                                      ['apps.restart', { app: 'gitea' }]])
    end

    it "records the helper's reason when it fails" do
      helper_fails('apps.start', 'docker exited 1: No such container: amahi-gitea')
      expect { app.start! }.to raise_error(DockerApp::ContainerError, /No such container/)
      expect(app.reload).to have_attributes(status: 'error', error_message: 'docker exited 1: No such container: amahi-gitea')
    end
  end

  describe 'uninstalling' do
    it 'removes the container, keeping the data, and forgets the app' do
      build_app.save!
      DockerApp.uninstall('gitea')
      expect(Privileged.calls).to eq([['apps.uninstall', { app: 'gitea', delete_data: false }]])
      expect(DockerApp.find_by(identifier: 'gitea')).to be_nil
    end

    it 'deletes the data when asked, installed or not' do
      DockerApp.uninstall('gitea', delete_data: true)
      expect(Privileged.calls).to eq([['apps.uninstall', { app: 'gitea', delete_data: true }]])
    end

    it 'keeps the record, with the reason, when the helper fails' do
      build_app.save!
      helper_fails('apps.uninstall', "docker isn't installed")
      expect { build_app.uninstall! }.to raise_error(DockerApp::ContainerError, "docker isn't installed")
      expect(DockerApp.find_by(identifier: 'gitea')).to have_attributes(status: 'error', error_message: "docker isn't installed")
    end
  end

  describe '.refresh_statuses!' do
    def docker_reports(apps, docker: true)
      allow(Privileged).to receive(:call).with('apps.status').and_return('ok' => true, 'docker' => docker, 'apps' => apps)
    end

    before do
      build_app(identifier: 'gitea', status: 'running').save!
      build_app(identifier: 'jellyfin', status: 'running').save!
      build_app(identifier: 'vaultwarden', status: 'stopped').save!
      build_app(identifier: 'transmission', status: 'installing').save!
      build_app(identifier: 'uptimekuma', status: 'error', error_message: 'docker exited 1: pull access denied').save!
    end

    it "follows Docker: stopped, started, gone, and leaves installs and earlier errors alone" do
      docker_reports({ 'gitea' => { 'state' => 'exited' }, 'vaultwarden' => { 'state' => 'running' } })
      DockerApp.refresh_statuses!
      statuses = DockerApp.all.to_h { |app| [app.identifier, [app.status, app.error_message]] }
      expect(statuses).to eq('gitea' => ['stopped', nil], 'vaultwarden' => ['running', nil],
                             'jellyfin' => ['error', 'Its container is gone: install it again'],
                             'transmission' => ['installing', nil],
                             'uptimekuma' => ['error', 'docker exited 1: pull access denied'])
    end

    it "changes nothing when Docker can't be asked" do
      docker_reports({}, docker: false)
      expect { DockerApp.refresh_statuses! }.not_to(change { DockerApp.pluck(:status) })
      allow(Privileged).to receive(:call).with('apps.status').and_raise(Privileged::Error.new('apps.status', 'sudo failed'))
      expect { DockerApp.refresh_statuses! }.not_to(change { DockerApp.pluck(:status) })
    end
  end
end

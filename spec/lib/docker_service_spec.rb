require 'rails_helper'
require 'docker_service'

RSpec.describe DockerService do
  # All tests run in non-production (test env), so production? returns false

  describe 'DockerError' do
    it 'is a StandardError subclass' do
      expect(DockerService::DockerError.new).to be_a(StandardError)
    end

    it 'can be raised with a message' do
      expect { raise DockerService::DockerError, 'boom' }.to raise_error(DockerService::DockerError, 'boom')
    end
  end

  describe '.installed?' do
    it 'returns false in test environment' do
      expect(DockerService.installed?).to be false
    end
  end

  describe '.running?' do
    it 'returns false in test environment' do
      expect(DockerService.running?).to be false
    end
  end

  describe '.enabled?' do
    it 'returns false when not installed and not running' do
      expect(DockerService.enabled?).to be false
    end

    it 'requires both installed? and running? to be true' do
      allow(DockerService).to receive(:installed?).and_return(true)
      allow(DockerService).to receive(:running?).and_return(false)
      expect(DockerService.enabled?).to be false
    end

    it 'returns true when both installed and running' do
      allow(DockerService).to receive(:installed?).and_return(true)
      allow(DockerService).to receive(:running?).and_return(true)
      expect(DockerService.enabled?).to be true
    end
  end

  describe '.status' do
    it 'returns a hash with expected keys' do
      result = DockerService.status
      expect(result).to be_a(Hash)
      expect(result).to have_key(:installed)
      expect(result).to have_key(:running)
      expect(result).to have_key(:version)
    end

    it 'returns dummy_status in test (all false/nil)' do
      result = DockerService.status
      expect(result[:installed]).to be false
      expect(result[:running]).to be false
      expect(result[:version]).to be_nil
    end
  end

  describe '.version' do
    it 'returns a stub string in test environment' do
      result = DockerService.version
      expect(result).to be_a(String)
      expect(result).to include('stub')
    end
  end

  describe '.install!' do
    it 'returns true in test environment' do
      expect(DockerService.install!).to be true
    end
  end

  describe '.start!' do
    it 'returns true in test environment' do
      expect(DockerService.start!).to be true
    end
  end

  describe '.stop!' do
    it 'returns true in test environment' do
      expect(DockerService.stop!).to be true
    end
  end

  describe '.restart!' do
    it 'returns true in test environment' do
      expect(DockerService.restart!).to be true
    end
  end

  describe 'in production' do
    before { allow(DockerService).to receive(:production?).and_return(true) }

    # The web app's user isn't added to the docker group: apps run only through the helper.
    it "installs from Docker's repository through the root helper and starts it" do
      lines = []
      DockerService.install! { |line| lines << line }
      expect(Privileged.calls).to eq([
                                       ['packages.add_repository', { repository: 'docker' }],
                                       ['packages.install', { packages: %w[docker-ce docker-ce-cli containerd.io] }],
                                       ['services.enable', { service: 'docker' }]
                                     ])
      expect(lines).to include('Installing Docker Engine...')
    end

    it "stops with the helper's reason" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('packages.add_repository', 'curl exited 6'))
      expect { DockerService.install! }.to raise_error(DockerService::DockerError, 'curl exited 6')
    end

    it 'starts, stops and restarts Docker through the helper' do
      DockerService.start!
      DockerService.stop!
      DockerService.restart!
      expect(Privileged.calls.map(&:first)).to eq(%w[services.start services.stop services.restart])
    end

    it "asks systemd whether Docker's service is up, without Docker's socket" do
      allow(Open3).to receive(:capture3).with('systemctl', 'is-active', 'docker')
                                        .and_return(["active\n", '', instance_double(Process::Status, success?: true)])
      expect(DockerService.running?).to be true
      allow(Open3).to receive(:capture3).with('systemctl', 'is-active', 'docker')
                                        .and_return(["inactive\n", '', instance_double(Process::Status, success?: false)])
      expect(DockerService.running?).to be false
    end
  end
end

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

  describe 'constants' do
    it 'defines KEYRING_PATH' do
      expect(DockerService::KEYRING_PATH).to be_a(String)
    end

    it 'defines SOURCES_PATH' do
      expect(DockerService::SOURCES_PATH).to be_a(String)
    end

    it 'defines GPG_URL' do
      expect(DockerService::GPG_URL).to include('docker.com')
    end
  end
end

require 'spec_helper'
require 'container_service'

RSpec.describe ContainerService do

  describe '.available?' do
    it 'returns true in non-production' do
      expect(ContainerService.available?).to be true
    end
  end

  describe '.list' do
    it 'returns empty array in non-production' do
      expect(ContainerService.list).to eq([])
    end
  end

  describe '.find' do
    it 'returns dummy container in non-production' do
      result = ContainerService.find('test-app')
      expect(result[:name]).to eq('test-app')
      expect(result[:status]).to eq('stopped')
    end
  end

  describe '.pull_image' do
    it 'returns true in non-production' do
      expect(ContainerService.pull_image('nginx:latest')).to be true
    end
  end

  describe '.create' do
    it 'returns dummy container in non-production' do
      result = ContainerService.create(
        image: 'nginx:latest',
        name: 'test-nginx',
        ports: { '80' => '8080' },
        volumes: {},
        environment: {}
      )
      expect(result[:name]).to eq('test-nginx')
    end
  end

  describe '.start' do
    it 'returns true in non-production' do
      expect(ContainerService.start('test-app')).to be true
    end
  end

  describe '.stop' do
    it 'returns true in non-production' do
      expect(ContainerService.stop('test-app')).to be true
    end
  end

  describe '.restart' do
    it 'returns true in non-production' do
      expect(ContainerService.restart('test-app')).to be true
    end
  end

  describe '.remove' do
    it 'returns true in non-production' do
      expect(ContainerService.remove('test-app')).to be true
    end
  end

  describe '.status' do
    it 'returns stopped in non-production' do
      expect(ContainerService.status('test-app')).to eq('stopped')
    end
  end

  describe '.logs' do
    it 'returns dummy logs in non-production' do
      expect(ContainerService.logs('test-app')).to include('test-app')
    end
  end

  describe '.stats' do
    it 'returns zero stats in non-production' do
      result = ContainerService.stats('test-app')
      expect(result[:cpu]).to eq(0.0)
      expect(result[:memory]).to eq(0)
    end
  end
end

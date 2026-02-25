require 'rails_helper'

RSpec.describe ContainerService do
  # In non-production (test env), most methods return dummies/stubs

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
    it 'returns a dummy container hash' do
      result = ContainerService.find('amahi-test')
      expect(result).to include(:name, :status, :image, :id)
      expect(result[:name]).to eq('amahi-test')
    end
  end

  describe '.pull_image' do
    it 'returns true in non-production' do
      expect(ContainerService.pull_image('nginx:latest')).to be true
    end
  end

  describe '.create' do
    it 'returns a dummy container in non-production' do
      result = ContainerService.create(name: 'amahi-test', image: 'nginx:latest')
      expect(result).to include(:name, :status)
      expect(result[:name]).to eq('amahi-test')
    end
  end

  describe '.start' do
    it 'returns true in non-production' do
      expect(ContainerService.start('amahi-test')).to be true
    end
  end

  describe '.stop' do
    it 'returns true in non-production' do
      expect(ContainerService.stop('amahi-test')).to be true
    end
  end

  describe '.restart' do
    it 'returns true in non-production' do
      expect(ContainerService.restart('amahi-test')).to be true
    end
  end

  describe '.remove' do
    it 'returns true in non-production' do
      expect(ContainerService.remove('amahi-test')).to be true
    end
  end

  describe '.status' do
    it 'returns stopped in non-production' do
      expect(ContainerService.status('amahi-test')).to eq('stopped')
    end
  end

  describe '.logs' do
    it 'returns dummy logs in non-production' do
      logs = ContainerService.logs('amahi-test')
      expect(logs).to include('amahi-test')
    end
  end

  describe '.stats' do
    it 'returns dummy stats in non-production' do
      stats = ContainerService.stats('amahi-test')
      expect(stats).to include(:cpu, :memory)
      expect(stats[:cpu]).to eq(0.0)
    end
  end

  describe '.calculate_cpu_percent' do
    it 'returns 0 when deltas are zero' do
      stats = {
        'cpu_stats' => { 'cpu_usage' => { 'total_usage' => 100 }, 'system_cpu_usage' => 100, 'online_cpus' => 2 },
        'precpu_stats' => { 'cpu_usage' => { 'total_usage' => 100 }, 'system_cpu_usage' => 100 }
      }
      expect(ContainerService.send(:calculate_cpu_percent, stats)).to eq(0.0)
    end

    it 'calculates percentage correctly' do
      stats = {
        'cpu_stats' => { 'cpu_usage' => { 'total_usage' => 200 }, 'system_cpu_usage' => 1000, 'online_cpus' => 4 },
        'precpu_stats' => { 'cpu_usage' => { 'total_usage' => 100 }, 'system_cpu_usage' => 500 }
      }
      # cpu_delta=100, sys_delta=500, 4 cpus => (100/500)*4*100 = 80.0
      expect(ContainerService.send(:calculate_cpu_percent, stats)).to eq(80.0)
    end
  end
end

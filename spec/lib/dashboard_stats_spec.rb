require 'rails_helper'

RSpec.describe DashboardStats do
  describe '.summary' do
    it 'returns a hash with all sections' do
      summary = DashboardStats.summary
      expect(summary).to include(:system, :resources, :services, :storage, :counts)
    end
  end

  describe '.system_info' do
    it 'returns hostname, uptime, and os' do
      info = DashboardStats.system_info
      expect(info).to include(:hostname, :uptime, :os)
      expect(info[:hostname]).to be_a(String)
      expect(info[:os]).to be_a(String)
    end
  end

  describe '.resource_usage' do
    it 'returns cpu, memory, and disk' do
      usage = DashboardStats.resource_usage
      expect(usage).to include(:cpu, :memory, :disk)
    end

    it 'cpu has percent and detail' do
      cpu = DashboardStats.resource_usage[:cpu]
      expect(cpu).to include(:percent, :detail)
      expect(cpu[:percent]).to be_a(Integer)
    end

    it 'memory has percent and detail' do
      mem = DashboardStats.resource_usage[:memory]
      expect(mem).to include(:percent, :detail)
    end

    it 'disk has percent and detail' do
      disk = DashboardStats.resource_usage[:disk]
      expect(disk).to include(:percent, :detail)
    end
  end

  describe '.service_status' do
    it 'returns an array of service hashes' do
      services = DashboardStats.service_status
      expect(services).to be_an(Array)
      services.each do |svc|
        expect(svc).to include(:name, :unit, :running, :status)
      end
    end

    it 'always includes core services' do
      names = DashboardStats.service_status.map { |s| s[:name] }
      expect(names).to include('Samba', 'MariaDB')
    end
  end

  describe '.storage_summary' do
    it 'returns storage counts' do
      summary = DashboardStats.storage_summary
      expect(summary).to include(:shares_count, :total_files, :pool_drives, :greyhole_installed)
      expect(summary[:shares_count]).to be_a(Integer)
    end
  end

  describe '.entity_counts' do
    it 'returns entity counts' do
      counts = DashboardStats.entity_counts
      expect(counts).to include(:users, :shares, :dns_aliases, :docker_apps)
      counts.each_value { |v| expect(v).to be_a(Integer) }
    end

    it 'counts created shares' do
      create(:share)
      create(:share)
      expect(DashboardStats.entity_counts[:shares]).to be >= 2
    end
  end
end

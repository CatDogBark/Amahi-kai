require 'spec_helper'

RSpec.describe DnsIpSetting, type: :model do
  before do
    Setting.where(name: %w[dns dns_ip_1 dns_ip_2]).destroy_all
  end

  describe 'validations' do
    it 'accepts valid IPv4 addresses' do
      setting = DnsIpSetting.new(name: 'dns_ip_test', value: '8.8.8.8', kind: Setting::NETWORK)
      expect(setting).to be_valid
    end

    it 'rejects invalid IP addresses' do
      setting = DnsIpSetting.new(name: 'dns_ip_test', value: 'not-an-ip', kind: Setting::NETWORK)
      expect(setting).not_to be_valid
    end

    it 'rejects blank value' do
      setting = DnsIpSetting.new(name: 'dns_ip_test', value: '', kind: Setting::NETWORK)
      expect(setting).not_to be_valid
    end
  end

  describe '.dns_ips' do
    it 'returns Cloudflare IPs when dns is cloudflare' do
      Setting.find_or_create_by!(name: 'dns', kind: Setting::NETWORK).update!(value: 'cloudflare')
      expect(DnsIpSetting.dns_ips).to eq(%w[1.1.1.1 1.0.0.1])
    end

    it 'returns Google IPs when dns is google' do
      Setting.find_or_create_by!(name: 'dns', kind: Setting::NETWORK).update!(value: 'google')
      expect(DnsIpSetting.dns_ips).to eq(%w[8.8.8.8 8.8.4.4])
    end

    it 'returns custom IPs for unknown provider' do
      Setting.find_or_create_by!(name: 'dns', kind: Setting::NETWORK).update!(value: 'custom')
      ips = DnsIpSetting.dns_ips
      expect(ips).to be_an(Array)
      expect(ips.length).to eq(2)
    end
  end

  describe '.custom_dns_ips' do
    it 'returns default IPs when none configured' do
      ips = DnsIpSetting.custom_dns_ips
      expect(ips).to eq(%w[1.1.1.1 1.0.0.1])
    end

    it 'returns configured IPs when set' do
      Setting.find_or_create_by!(name: 'dns_ip_1', kind: Setting::NETWORK).update!(value: '9.9.9.9')
      Setting.find_or_create_by!(name: 'dns_ip_2', kind: Setting::NETWORK).update!(value: '149.112.112.112')
      ips = DnsIpSetting.custom_dns_ips
      expect(ips).to include('9.9.9.9')
      expect(ips).to include('149.112.112.112')
    end
  end
end

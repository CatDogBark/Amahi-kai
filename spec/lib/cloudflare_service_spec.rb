require 'rails_helper'

RSpec.describe CloudflareService do
  describe '.status' do
    it 'returns dummy status in non-production' do
      status = CloudflareService.status
      expect(status).to be_a(Hash)
      expect(status[:installed]).to eq(false)
      expect(status[:running]).to eq(false)
      expect(status[:token_configured]).to eq(false)
    end
  end

  describe '.installed?' do
    it 'returns false in non-production' do
      expect(CloudflareService.installed?).to eq(false)
    end
  end

  describe '.running?' do
    it 'returns false in non-production' do
      expect(CloudflareService.running?).to eq(false)
    end
  end

  describe '.enabled?' do
    it 'returns false when not installed or running' do
      expect(CloudflareService.enabled?).to eq(false)
    end
  end

  describe '.token_configured?' do
    it 'returns true in non-production' do
      expect(CloudflareService.token_configured?).to eq(true)
    end
  end

  describe '.install!' do
    it 'returns true in non-production' do
      expect(CloudflareService.install!).to eq(true)
    end
  end

  describe '.configure!' do
    it 'returns true in non-production' do
      expect(CloudflareService.configure!('test-token')).to eq(true)
    end
  end

  describe '.start!' do
    it 'returns true in non-production' do
      expect(CloudflareService.start!).to eq(true)
    end
  end

  describe '.stop!' do
    it 'returns true in non-production' do
      expect(CloudflareService.stop!).to eq(true)
    end
  end

  describe '.restart!' do
    it 'returns true in non-production' do
      expect(CloudflareService.restart!).to eq(true)
    end
  end
end

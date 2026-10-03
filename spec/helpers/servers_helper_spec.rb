require 'rails_helper'

RSpec.describe ServersHelper, type: :helper do
  describe '#duration_words' do
    it 'shows the two largest units' do
      expect(helper.duration_words(1.day + 15.hours + 34.minutes)).to eq('1 day, 15 hours')
      expect(helper.duration_words(2.hours + 5.minutes)).to eq('2 hours, 5 minutes')
      expect(helper.duration_words(3.days + 20.minutes)).to eq('3 days, 20 minutes')
      expect(helper.duration_words(45)).to eq('under a minute')
      expect(helper.duration_words(nil)).to be_nil
    end
  end

  describe '#service_state_badge' do
    def service(props)
      SystemServices::Service.new({ key: 'x', name: 'X', unit: 'x' }, props)
    end

    it 'labels each state' do
      expect(helper.service_state_badge(service('ActiveState' => 'active'))).to include('Running', 'bg-success')
      expect(helper.service_state_badge(service('ActiveState' => 'failed'))).to include('Failed', 'bg-danger')
      expect(helper.service_state_badge(service('ActiveState' => 'inactive'))).to include('Stopped')
      expect(helper.service_state_badge(service('LoadState' => 'not-found'))).to include('Not installed')
    end
  end
end

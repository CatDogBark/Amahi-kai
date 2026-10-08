require 'rails_helper'

# config/locales/en.yml: a value written over several lines must mean to be (a line left from a
# removed value once joined onto the key above it: the Apps tab read "Available Any data
# associated with this application WILL BE DELETED.").
RSpec.describe 'The English translations' do
  let(:en) { YAML.load_file(Rails.root.join('config/locales/en.yml'))['en'] }

  it 'span several lines only where they mean to' do
    multi_line = en.select { |_key, value| value.is_a?(String) && value.include?("\n") }.keys
    expect(multi_line).to contain_exactly('this_will_power_off', 'this_will_reboot')
  end
end

require 'rails_helper'

RSpec.describe SettingsHelper, type: :helper do
  describe '#update_change_link' do
    it "links a change's pull request number" do
      html = helper.update_change_link('Drive temperatures through the helper (#35)')
      expect(html).to include('Drive temperatures through the helper ')
      expect(html).to include('href="https://github.com/CatDogBark/Amahi-kai/pull/35"', '>#35</a>')
    end

    it 'escapes the title and leaves titles without a number alone' do
      expect(helper.update_change_link('<b>x</b> (#1)')).to include('&lt;b&gt;x&lt;/b&gt;')
      expect(helper.update_change_link('Plain title')).to eq('Plain title')
    end
  end
end

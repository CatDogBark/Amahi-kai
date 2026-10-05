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

  describe '#changelog_entry' do
    it 'shows **bold** and `code`, including code inside bold' do
      html = helper.changelog_entry("**The swap file is added to `/etc/fstab`.** Then it's used.")
      expect(html).to eq("<strong>The swap file is added to <code>/etc/fstab</code>.</strong> Then it&#39;s used.")
    end

    it 'escapes everything else, and keeps asterisks in code from starting bold text' do
      expect(helper.changelog_entry('<img src=x> `a**b` and `c**d`')).to eq('&lt;img src=x&gt; <code>a&#42;&#42;b</code> and <code>c&#42;&#42;d</code>')
      expect(helper.changelog_entry('**<b>x</b>**')).to eq('<strong>&lt;b&gt;x&lt;/b&gt;</strong>')
    end
  end
end

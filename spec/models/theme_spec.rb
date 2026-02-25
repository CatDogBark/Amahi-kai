require 'rails_helper'

RSpec.describe Theme, type: :model do
  describe '.available' do
    it 'returns an array of themes' do
      themes = Theme.available
      expect(themes).to be_an(Array)
    end

    it 'includes themes from the filesystem' do
      themes = Theme.available
      # At minimum the default and amahi-kai themes should exist
      names = themes.map(&:name)
      expect(names.length).to be >= 1
    end
  end

  describe '.dir2theme' do
    it 'loads a theme from a directory' do
      # amahi-kai theme should exist
      theme = Theme.dir2theme('amahi-kai')
      expect(theme).to be_a(Theme)
      expect(theme.css).to eq('amahi-kai')
      expect(theme).to be_persisted
    end

    it 'raises when directory does not exist' do
      expect {
        Theme.dir2theme('nonexistent-theme-xyz')
      }.to raise_error(RuntimeError, /does not exist/)
    end
  end

  describe 'lifecycle' do
    it 'can be created with name and css' do
      theme = Theme.create!(name: 'Test Theme', css: 'test-theme-dir')
      expect(theme).to be_persisted
      expect(theme.name).to eq('Test Theme')
    end
  end
end

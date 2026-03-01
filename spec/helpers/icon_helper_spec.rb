require 'rails_helper'

RSpec.describe IconHelper, type: :helper do
  describe '#lucide_icon' do
    it 'returns empty string for nonexistent icon' do
      expect(helper.lucide_icon('nonexistent_icon_xyz')).to eq('')
    end

    it 'returns SVG for existing icon' do
      # Use an icon we know exists
      icons_dir = Rails.root.join('app', 'assets', 'images', 'icons')
      icon_files = Dir.glob(icons_dir.join('*.svg'))
      skip 'No icon files found' if icon_files.empty?

      icon_name = File.basename(icon_files.first, '.svg')
      result = helper.lucide_icon(icon_name)
      expect(result).to include('<svg')
    end

    it 'sets custom size' do
      icons_dir = Rails.root.join('app', 'assets', 'images', 'icons')
      icon_files = Dir.glob(icons_dir.join('*.svg'))
      skip 'No icon files found' if icon_files.empty?

      icon_name = File.basename(icon_files.first, '.svg')
      result = helper.lucide_icon(icon_name, size: 32)
      expect(result).to include('width="32"')
    end

    it 'adds CSS class' do
      icons_dir = Rails.root.join('app', 'assets', 'images', 'icons')
      icon_files = Dir.glob(icons_dir.join('*.svg'))
      skip 'No icon files found' if icon_files.empty?

      icon_name = File.basename(icon_files.first, '.svg')
      result = helper.lucide_icon(icon_name, css_class: 'my-class')
      expect(result).to include('my-class')
    end

    it 'returns html_safe string' do
      icons_dir = Rails.root.join('app', 'assets', 'images', 'icons')
      icon_files = Dir.glob(icons_dir.join('*.svg'))
      skip 'No icon files found' if icon_files.empty?

      icon_name = File.basename(icon_files.first, '.svg')
      result = helper.lucide_icon(icon_name)
      expect(result).to be_html_safe
    end
  end
end

require 'rails_helper'

# Production reads public/assets/.sprockets-manifest-*.json on every boot, including the
# `rails db:migrate` that System Update runs. Sprockets 4.2 passed json 3 an option it no
# longer accepts, so once assets were compiled the app couldn't start. Tests compile assets
# on demand and never read a manifest, so this reads one the way production does.
RSpec.describe 'compiled assets manifest' do
  it 'can be read with the bundled json' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".sprockets-manifest-#{'0' * 32}.json"),
                 JSON.generate('files' => {}, 'assets' => { 'login.css' => 'login-abc.css' }))

      manifest = Sprockets::Manifest.new(Rails.application.assets, dir)

      expect(manifest.assets).to eq('login.css' => 'login-abc.css')
    end
  end
end

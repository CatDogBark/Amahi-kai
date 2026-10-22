require 'rails_helper'

# The stylesheets are plain CSS (no Sass compiler since PR Q), and Bootstrap is its official
# 5.3.8 build, vendored.
RSpec.describe 'stylesheets' do
  it 'has no Sass sources in the asset pipeline' do
    expect(Dir[Rails.root.join('{app,vendor,lib}/assets/**/*.{scss,sass}')]).to eq([])
  end

  it "builds application.css from Bootstrap's official CSS, then the app's own" do
    css = Rails.application.assets['application.css'].to_s
    expect(css).to include('Bootstrap  v5.3.8')
    expect(css.index('Bootstrap  v5.3.8')).to be < css.index(".amahi-toast")
    expect(css).to include('.amahi-toast').or include('#toast-container')
  end

  it "builds the sign-in page's stylesheet on the app's theme, which the page loads first" do
    css = Rails.application.assets['login.css'].to_s
    expect(css).to include('body.login').and include('var(--kai-mint)')
    expect(css).not_to include('#0a6e8a')
    layout = File.read(Rails.root.join('app/views/layouts/login.html.slim'))
    expect(layout.index('stylesheet_link_tag "application"')).to be < layout.index('stylesheet_link_tag "login"')
  end

  it "loads Bootstrap's JavaScript (with Popper) from the same release" do
    js = Rails.application.assets['application.js'].to_s
    expect(js).to include('Bootstrap v5.3.8')
    expect(js).to include('createPopper')
  end
end

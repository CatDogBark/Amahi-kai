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
    expect(css.index('Bootstrap  v5.3.8')).to be < css.index('.nav_hover:hover')
    expect(css).to include('.amahi-toast').or include('#toast-container')
  end

  it 'builds the login stylesheet with its light and dark colours' do
    css = Rails.application.assets['login.css'].to_s
    expect(css).to include('--login-submit-bg: #0a6e8a;').and include('--login-submit-bg: #1a9fc2;')
  end

  it "loads Bootstrap's JavaScript (with Popper) from the same release" do
    js = Rails.application.assets['application.js'].to_s
    expect(js).to include('Bootstrap v5.3.8')
    expect(js).to include('createPopper')
  end
end

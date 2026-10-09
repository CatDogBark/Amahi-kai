require 'rails_helper'

# Apps in a real browser: without Docker (as outside production), the Install Docker window
# streams the simulated install and finishes; the installed apps page loads clean.
RSpec.describe 'Apps', type: :system do
  it 'offers to install Docker, and its window streams to the end' do
    sign_in_as_admin
    visit '/apps'
    expect(page).to have_text('Docker is not installed')
    click_button 'Install Docker'
    within('#docker-install-modal') do
      expect(page).to have_css('#docker-output', text: 'Installing Docker Engine')
      expect(page).to have_css('#docker-status', text: '✓ Done', wait: 30) # the simulated install takes a few seconds
      expect(page).to have_button('Close & Refresh')
    end
  end

  it 'shows the installed apps page' do
    sign_in_as_admin
    visit '/apps/installed_apps'
    expect(page).to have_css('.kai-mainnav .kai-navlink[aria-current="page"]', text: 'Apps')
  end
end

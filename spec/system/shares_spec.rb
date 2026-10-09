require 'rails_helper'

# Setup → Shares in a real browser: a share's card and its scripts (shares.js, through the
# data-call dispatcher), and creating a share.
RSpec.describe 'Shares', type: :system do
  let(:folder) { Dir.mktmpdir('amahi-share') }
  let!(:share) { create(:share, name: 'Photos', path: folder) }

  after { FileUtils.rm_rf(folder) }

  it "opens a share's card, counts its size, changes its pool copies and saves Samba settings" do
    File.write("#{folder}/a.txt", 'x' * 2048)
    Setting.set('advanced', '1')
    sign_in_as_admin
    visit '/shares'

    find("#whole_share_#{share.id} .share-name", text: 'Photos').click
    within("#whole_share_#{share.id}") do
      expect(page).to have_css('.share-section-title', text: /access/i)

      click_link 'Get the size'
      expect(page).to have_css("#size-area-#{share.id} strong", text: /KB|Bytes/)

      expect(page).to have_css("#pool-copies-#{share.id}", text: 'Off')
      find("#pool-controls-#{share.id} [data-pool-action='plus']").click
      expect(page).to have_css("#pool-copies-#{share.id}", text: '1 copy')
      expect(share.reload.disk_pool_copies).to eq(1)

      fill_in "extras-textarea-#{share.id}", with: 'hide dot files = yes'
      click_button 'Save'
      expect(page).to have_css("#extras-msg-#{share.id}", text: 'Saved!', visible: :visible)
      expect(share.reload.extras).to eq('hide dot files = yes')
    end
  end

  it 'creates a share from the form and lists it without a reload' do
    sign_in_as_admin
    visit '/shares'
    click_button 'New Share'
    fill_in 'share[name]', with: 'Music'
    click_button 'Create'
    expect(page).to have_css('#shares-table .share-name', text: 'Music')
    expect(Share.find_by(name: 'Music')).to be_present
    expect(page.current_path).to eq('/shares')
  end
end

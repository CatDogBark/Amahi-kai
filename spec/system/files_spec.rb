require 'rails_helper'

# Files in a real browser: the shares as cards, a share's folder with the row links, the
# selected file's panel and the grid view (file_browser_controller.js).
RSpec.describe 'Files', type: :system do
  let(:folder) { Dir.mktmpdir('amahi-files') }
  let!(:share) { create(:share, name: 'Docs', path: folder) }

  before do
    Dir.mkdir("#{folder}/Reports")
    File.write("#{folder}/Reports/q1.txt", "quarter one\n")
    File.write("#{folder}/notes.txt", "some notes\n")
    # A 1×1 PNG, so the kind is a picture
    File.binwrite("#{folder}/dot.png", Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))
  end

  after { FileUtils.rm_rf(folder) }

  it 'lists the shares, opens one, selects a file and switches to the grid' do
    sign_in_as_admin
    visit '/files'
    expect(page).to have_css('.fb-card .fb-card-name', text: 'Docs')
    expect(page).to have_css('#trash-entry')

    click_link 'Docs'
    expect(page).to have_css('.fb-breadcrumbs .fb-crumb-current', text: 'Docs')
    expect(page).to have_css('.fb-item', count: 3)
    expect(page).to have_css('.fb-statusbar', text: '1 folder, 2 files')

    # A file's row shows it in the panel
    find('.fb-item[data-name="notes.txt"] .fb-file-link').click
    within('.fb-details') do
      expect(page).to have_css('.fb-details-name', text: 'notes.txt')
      expect(page).to have_css('.fb-details-kind', text: 'Text')
      expect(page).to have_link('Download')
    end

    # The grid shows pictures as themselves; the choice is remembered
    find('.fb-viewbtn[data-view="grid"]').click
    expect(page).to have_css('.fb-listing.fb-grid')
    expect(page).to have_css('.fb-item[data-name="dot.png"] .fb-item-icon img')
    visit page.current_path
    expect(page).to have_css('.fb-listing.fb-grid')

    # A folder's row opens it
    find('.fb-item[data-name="Reports"] .fb-folder-link').click
    expect(page).to have_css('.fb-crumb-current', text: 'Reports')
    expect(page).to have_css('.fb-item[data-name="q1.txt"]')
  end
end

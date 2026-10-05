require 'rails_helper'

# Tooltips are Bootstrap's (data-tip, tooltips.js): they show after 150 ms and extra
# information is marked. The browser's own title tooltip waits about a second and looks like
# plain text, so no element on these pages may have one (the page <title> and the search
# <link> aren't tooltips).
RSpec.describe 'Tooltips', type: :request do
  def pages
    %w[/ /disks /disks/devices /disks/mounts /disks/storage_pool /disks/pools /settings /settings/system_status
       /settings/servers /settings/jobs /settings/themes /shares /users]
  end

  before do
    login_as_admin
    Setting.set('advanced', '1')
    allow(DiskManager).to receive(:devices).and_return([])
    allow(StoragePools).to receive(:drives).and_return([])
  end

  it 'uses data-tip, never the title attribute' do
    pages.each do |path|
      get path
      expect(response).to have_http_status(:ok), path
      html = Nokogiri::HTML(response.body)
      titled = html.css('[title]').reject { |el| el.name == 'link' && el['rel'] == 'search' }
      expect(titled.map { |el| el.to_s[0, 120] }).to be_empty, path
      expect(html.css('[data-tip]')).not_to be_empty, path # the header's buttons at least
    end
  end

  it 'lets keyboard users reach marked information' do
    get '/settings/servers'
    marked = Nokogiri::HTML(response.body).css('.tip-info, .tip-text')
    expect(marked.reject { |el| %w[a button].include?(el.name) || el['tabindex'] == '0' }).to be_empty
  end
end

require 'rails_helper'

# The Trash, beside the shares in the file browser: Greyhole's trash, for admins.
RSpec.describe 'Trash', type: :request do
  let(:item) { Trash::Item.new(kind: :pool, share: 'Photos', path: '2026/beach.jpg', bytes: 2048, trashed_at: 2.hours.ago, copies: 2) }

  before do
    create(:share, name: 'Photos', disk_pool_copies: 2)
    allow(Trash).to receive(:contents).and_return(
      items: [item, Trash::Item.new(kind: :pool, share: 'Old', path: 'a.txt', bytes: 10, trashed_at: 1.day.ago, copies: 1)], count: 2, space: 4096
    )
  end

  it 'is for admins only' do
    login_as(create(:user))
    get '/files/trash'
    expect(response).to redirect_to(new_user_session_url)
    post '/files/trash/empty'
    expect(Privileged.calls).to eq([])
  end

  describe 'as an admin' do
    before { login_as_admin }

    it "lists the trash's files, with Restore for the ones whose share is pooled, Delete and Empty trash" do
      get '/files/trash'
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('.fb-breadcrumbs').text.squish).to eq('Shares Trash')
      expect(page.at_css('#trash-summary-bar').text.squish).to include('2 files', '4 KB')
      rows = page.css('tr.trash-item')
      expect(rows.first.text.squish).to include('Photos/2026/beach.jpg', '(2 copies)', '2 KB')
      expect(rows.first.css('button').map(&:text)).to eq(%w[Restore Delete])
      expect(rows.last.text).to include("Its share isn't pooled now")
      expect(rows.last.css('button').map(&:text)).to eq(['Delete'])
      expect(page.at_css('#empty-trash')['data-confirm']).to include('Delete all 2 files')
    end

    it "offers Restore for a share's recycle bin, and says how long files are kept, which it changes" do
      allow(Trash).to receive(:contents).and_return(
        items: [Trash::Item.new(kind: :share, share: 'Docs', path: 'q3.odt', bytes: 10, trashed_at: 1.hour.ago, copies: 1)], count: 1, space: 10
      )
      get '/files/trash'
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('tr.trash-item').css('button').map(&:text)).to eq(%w[Restore Delete])
      expect(page.at_css('tr.trash-item input[name=kind]')['value']).to eq('share')
      expect(page.at_css('#trash-about').text.squish).to include('deleted for good after 30 days')
      expect(page.css('#trash-days option').map(&:text)).to eq(['for 7 days', 'for 14 days', 'for 30 days', 'for 60 days', 'for 90 days', 'until emptied'])
      expect(page.at_css('#trash-days option[selected]').text).to eq('for 30 days')

      post '/files/trash/keep', params: { days: '14' }
      expect(response).to redirect_to('/files/trash')
      expect(flash[:notice]).to eq('The Trash keeps files for 14 days.')
      post '/files/trash/keep', params: { days: '45' }
      expect(flash[:error]).to include('lengths offered')
      expect(Privileged.calls).to eq([['trash.set_days', { days: 14 }]])
    end

    it "says when it's empty" do
      allow(Trash).to receive(:contents).and_return(items: [], count: 0, space: 0)
      get '/files/trash'
      expect(Nokogiri::HTML(response.body).at_css('#trash-summary').text).to include('The trash is empty.')
      expect(response.body).not_to include('empty-trash')
    end

    it 'restores, deletes and empties through the helper, saying what it did or why not' do
      create(:disk_pool_partition, path: '/mnt/storage-1')
      post '/files/trash/restore', params: { kind: 'pool', share: 'Photos', path: '2026/beach.jpg' }
      expect(response).to redirect_to('/files/trash')
      expect(flash[:notice]).to include('Photos/2026/beach.jpg is back in its share')
      post '/files/trash/delete', params: { kind: 'pool', share: 'Photos', path: '2026/beach.jpg' }
      post '/files/trash/empty'
      expect(flash[:notice]).to eq('The trash is empty.')
      expect(Privileged.calls).to eq([['greyhole.trash_restore', { share: 'Photos', path: '2026/beach.jpg' }],
                                      ['greyhole.trash_delete', { share: 'Photos', path: '2026/beach.jpg' }],
                                      ['greyhole.trash_empty', {}]])

      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('greyhole.trash_restore', 'Photos has a 2026/beach.jpg now'))
      post '/files/trash/restore', params: { kind: 'pool', share: 'Photos', path: '2026/beach.jpg' }
      expect(response).to redirect_to('/files/trash')
      expect(flash[:error]).to include('Photos has a 2026/beach.jpg now')
    end

    it "is below the shares in the file browser, apart from them, and on a pooled share's Features" do
      get '/files'
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('a#trash-entry')['href']).to eq('/files/trash')
      expect(page.at_css('#trash-entry-summary').text.squish).to eq('2 files · 4 KB')
      expect(page.css('#share-list .fb-card-name').map(&:text)).not_to include('Trash')

      get '/shares'
      share = Share.find_by(name: 'Photos')
      expect(Nokogiri::HTML(response.body).at_css("#share-trash-#{share.id}")['href']).to eq('/files/trash')
      expect(response.body).not_to include("toggleSharePreset(#{share.id}, 'recycle_bin')")
    end
  end

  it "isn't in a user's file browser" do
    login_as(create(:user))
    get '/files'
    expect(response.body).not_to include('trash-entry')
  end
end

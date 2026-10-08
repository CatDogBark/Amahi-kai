require 'rails_helper'

# The Trash, beside the shares in the file browser: Greyhole's trash, for admins.
RSpec.describe 'Trash', type: :request do
  let(:item) { GreyholeTrash::Item.new(share: 'Photos', path: '2026/beach.jpg', bytes: 2048, trashed_at: 2.hours.ago, copies: 2) }

  before do
    create(:share, name: 'Photos', disk_pool_copies: 2)
    allow(GreyholeTrash).to receive(:contents).and_return(
      items: [item, GreyholeTrash::Item.new(share: 'Old', path: 'a.txt', bytes: 10, trashed_at: 1.day.ago, copies: 1)], count: 2, space: 4096
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
      expect(page.at_css('.fb-breadcrumbs').text.squish).to eq('Shares / Trash')
      expect(page.at_css('#trash-summary-bar').text.squish).to include('2 files', '4 KB')
      rows = page.css('tr.trash-item')
      expect(rows.first.text.squish).to include('Photos/2026/beach.jpg', '(2 copies)', '2 KB')
      expect(rows.first.css('button').map(&:text)).to eq(%w[Restore Delete])
      expect(rows.last.text).to include("Its share isn't pooled now")
      expect(rows.last.css('button').map(&:text)).to eq(['Delete'])
      expect(page.at_css('#empty-trash')['data-confirm']).to include('Delete all 2 files')
    end

    it "says when it's empty" do
      allow(GreyholeTrash).to receive(:contents).and_return(items: [], count: 0, space: 0)
      get '/files/trash'
      expect(Nokogiri::HTML(response.body).at_css('#trash-summary').text).to include('The trash is empty.')
      expect(response.body).not_to include('empty-trash')
    end

    it 'restores, deletes and empties through the helper, saying what it did or why not' do
      post '/files/trash/restore', params: { share: 'Photos', path: '2026/beach.jpg' }
      expect(response).to redirect_to('/files/trash')
      expect(flash[:notice]).to include('Photos/2026/beach.jpg is back in its share')
      post '/files/trash/delete', params: { share: 'Photos', path: '2026/beach.jpg' }
      post '/files/trash/empty'
      expect(flash[:notice]).to eq('The trash is empty.')
      expect(Privileged.calls).to eq([['greyhole.trash_restore', { share: 'Photos', path: '2026/beach.jpg' }],
                                      ['greyhole.trash_delete', { share: 'Photos', path: '2026/beach.jpg' }],
                                      ['greyhole.trash_empty', {}]])

      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('greyhole.trash_restore', 'Photos has a 2026/beach.jpg now'))
      post '/files/trash/restore', params: { share: 'Photos', path: '2026/beach.jpg' }
      expect(response).to redirect_to('/files/trash')
      expect(flash[:error]).to include('Photos has a 2026/beach.jpg now')
    end

    it "is below the shares in the file browser, apart from them, and on a pooled share's Features" do
      get '/files'
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('#trash-entry a')['href']).to eq('/files/trash')
      expect(page.at_css('#trash-entry-summary').text.squish).to eq('2 files · 4 KB')
      expect(page.css('#share-list a').map(&:text).map(&:strip)).not_to include('Trash')

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

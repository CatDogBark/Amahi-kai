require 'rails_helper'

RSpec.describe "Tab bar", type: :request do
  before do
    login_as_admin
    Setting.set('advanced', '1')
  end

  def active_tabs
    Nokogiri::HTML(response.body).css('a.active-tab-link-style').map { |a| a['href'] }
  end

  def active_subtabs
    Nokogiri::HTML(response.body).css('a.active-subtab-link').map { |a| a['href'] }
  end

  it "highlights Network > Remote Access on the remote access page" do
    get '/network/remote_access'
    expect(active_tabs).to eq(['/network'])
    expect(active_subtabs).to eq(['/network/remote_access'])
  end

  it "highlights Network > Security on the security page" do
    get '/network/security'
    expect(active_tabs).to eq(['/network'])
    expect(active_subtabs).to eq(['/network/security'])
  end

  it "highlights Network > Leases on the network index" do
    get '/network'
    expect(active_tabs).to eq(['/network'])
    expect(active_subtabs).to eq(['/network'])
  end

  it "highlights Shares > Details on the shares page" do
    get '/shares'
    expect(active_tabs).to eq(['/shares'])
    expect(active_subtabs).to eq(['/shares'])
  end
end

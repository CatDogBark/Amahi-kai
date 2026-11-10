require 'rails_helper'

# Apps' logos, served by the NAS (AppLogosController, P4.10): a catalog app's comes with the
# catalog (config/logos in the copy here), an app of your own's is the one kept beside its file.
# Anyone signed in gets them (the dashboard shows them too); nothing else does.
RSpec.describe 'App logos', type: :request do
  let(:policy) { "default-src 'none'; img-src data:; style-src 'unsafe-inline'; sandbox" }

  before { AppCatalog.reload! }

  it "serves a catalog app's logo from the NAS, cached by the address that names it" do
    login_as_admin
    logo = AppCatalog.logo('jellyfin')
    get '/apps/logos/jellyfin', params: { v: logo[:version] }
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.body.b).to eq(File.binread(Rails.root.join('config/logos/jellyfin.png')))
    expect(response.headers['Content-Security-Policy']).to eq(policy)
    expect(response.headers['Cache-Control']).to include("max-age=#{1.year.to_i}")
    get '/apps/logos/jellyfin', params: { v: 'an-older-one' }
    expect(response.headers['Cache-Control']).to include('no-cache')
  end

  it 'serves them to anyone signed in, as the dashboard shows them, and to nobody else' do
    ensure_setup_completed!
    get '/apps/logos/gitea'
    expect(response).to redirect_to(new_user_session_path)
    login_as(create(:user))
    get '/apps/logos/gitea'
    expect(response).to have_http_status(:ok)
  end

  it "says there's none for an app without one, or an id that isn't one" do
    login_as_admin
    get '/apps/logos/portainer'
    expect(response).to have_http_status(:not_found)
    get '/apps/logos/Gitea'
    expect(response).to have_http_status(:not_found)
  end

  it 'is what the Apps page shows, for an installed app and a catalog card: nothing from another site' do
    allow(DockerService).to receive_messages(installed?: true, running?: true)
    login_as_admin
    create(:docker_app, identifier: 'jellyfin', name: 'Jellyfin', image: AppCatalog.find('jellyfin')[:image], status: 'running',
                        logo_url: 'https://example.com/jellyfin.png')
    get '/apps'
    expect(response.body).to include(%(src="#{AppCatalog.logo_url('transmission')}"), %(src="#{AppCatalog.logo_url('jellyfin')}"))
    expect(response.body).not_to match(%r{<img[^>]+src="https?://})
  end
end

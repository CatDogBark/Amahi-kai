require 'spec_helper'

# Apps of your own (CustomAppsController, docs/plans/apps.md): Add your own app, the review, your
# password again, and the root helper keeps the file (outside production, Privileged.call records
# the calls; the app files the helper writes are in tmp/custom-apps).
describe 'Apps of your own', type: :request do
  let(:custom) { Rails.root.join('tmp', 'custom-apps').to_s }
  let(:definitions) { Rails.root.join('tmp', 'app-definitions').to_s }
  let(:digest) { "sha256:#{'7f3c' * 16}" }
  let(:pinned) { "ghcr.io/mealie-recipes/mealie:v2.4.1@#{digest}" }
  let(:fields) do
    { name: 'Mealie', description: 'Recipes and meal plans', category: 'home', image: 'ghcr.io/mealie-recipes/mealie:v2.4.1',
      run_as: 'app', network: 'internet', memory: '1g', web: 'a',
      ports: { a: { host: '9925', container: '9000', protocol: 'tcp' } }, folders: { a: { name: 'data', path: '/app/data' } },
      settings: { a: { name: 'TZ', kind: 'timezone', value: '' }, b: { name: 'ALLOW_SIGNUP', kind: 'value', value: 'false' } },
      secrets: { a: { name: 'SECRET_KEY', label: 'Secret key' } }, capabilities: [''] }
  end
  let(:file) do
    <<~YAML
      name: Mealie
      description: Recipes and meal plans
      category: home
      image: #{pinned}
      run_as: app
      memory: 1g
      web_port: 9925
      ports:
      - host: 9925
        container: 9000
      folders:
      - name: data
        path: "/app/data"
      environment:
        TZ: "{{timezone}}"
        ALLOW_SIGNUP: 'false'
      secrets:
      - env: SECRET_KEY
        label: Secret key
    YAML
  end

  before do
    login_as_admin
    allow(DockerService).to receive(:installed?).and_return(true)
    allow(DockerService).to receive(:running?).and_return(true)
    allow(Etc).to receive(:nprocessors).and_return(8)
    allow_any_instance_of(AppVersions).to receive(:pin) { |_versions, image| image.include?('@') ? image : "#{image}@#{digest}" }
    CustomAppsController::PASSWORD_TRIES.clear
    FileUtils.rm_rf([custom, definitions])
    AppCatalog.reload!
  end

  after do
    FileUtils.rm_rf([custom, definitions])
    AppCatalog.reload!
  end

  def keep(id, text)
    FileUtils.mkdir_p(custom)
    File.write("#{custom}/#{id}.yml", text)
    AppCatalog.reload!
  end

  def saved_manifest
    Privileged.calls.find { |op, _args| op == 'apps.custom_save' }&.last&.dig(:manifest)
  end

  # A 1x1 PNG, as the form sends a picture chosen
  let(:png) { 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=' }

  def picture(bytes, name = 'logo.png')
    Rack::Test::UploadedFile.new(StringIO.new(bytes), 'application/octet-stream', true, original_filename: name)
  end

  describe 'on the Apps page' do
    it 'offers Add your own app' do
      get '/apps'
      expect(response.body).to include('id="add-your-own"', 'href="/apps/custom/new"')
    end

    it 'lists one of your own as Custom, with Edit and Remove, and a filter of its own' do
      keep('mealie', file)
      get '/apps'
      card = response.body[/<article[^>]*id="docker_app_mealie".*?<\/article>/m]
      expect(card).to include('Custom', "Added by you: Amahi-kai hasn't checked it.", 'href="/apps/custom/mealie/edit"',
                              '/apps/custom/mealie/remove')
      expect(response.body).to include('href="/apps?category=custom#add"')
      get '/apps', params: { category: 'custom' }
      expect(response.body).to include('id="docker_app_mealie"')
      expect(response.body).not_to include('id="docker_app_gitea"')
    end

    it "lists yours instead of the catalog's when the catalog has the same id" do
      keep('gitea', file.sub('name: Mealie', 'name: My Gitea'))
      get '/apps'
      expect(response.body).to include('My Gitea')
      expect(response.body.scan('id="docker_app_gitea"').size).to eq(1)
      expect(AppCatalog.find('gitea')).to include(custom: true, name: 'My Gitea')
    end

    it 'opens Install by itself for the app just added' do
      keep('mealie', file)
      get '/apps', params: { install: 'mealie' }
      expect(response.body).to match(/data-app-shares="mealie"[^>]*data-auto-open=""/)
    end
  end

  describe 'adding one' do
    it 'shows the form, with the limits this NAS gives' do
      get '/apps/custom/new'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Describe it', 'I have an app file', 'name="app[image]"', "7 of the NAS&#39;s 8 processors",
                                       'data-custom-template="ports"')
    end

    it 'reviews what it will be able to do, its image pinned, once the helper has checked it' do
      post '/apps/custom/review', params: { source: 'form', app: fields }
      expect(response).to have_http_status(:ok)
      expect(Privileged.calls).to eq([['apps.custom_check', { app: 'mealie', manifest: file }]])
      expect(response.body).to include('Review: Mealie', 'As its own user, with no kernel permissions',
                                       'ghcr.io/mealie-recipes/mealie:v2.4.1', 'This exact build (sha256:7f3c…7f3c)',
                                       'Port 9925 (its web page), from your network and Tailscale only',
                                       'One folder, data (in the app at /app/data), on the system disk',
                                       "2 settings, and 1 secret Amahi-kai makes and shows you on its page",
                                       "Up to 1 GB of memory, and 7 of the NAS&#39;s 8 processors",
                                       "It isn't from the Amahi-kai catalog", 'name="password"')
    end

    it 'gives an app that starts as root the permissions ticked, and says so' do
      post '/apps/custom/review', params: { source: 'form', app: fields.merge(run_as: 'image', capabilities: ['', 'CHOWN', 'SETUID', 'SYS_ADMIN']) }
      manifest = YAML.safe_load(Privileged.calls.last.last[:manifest])
      expect(manifest).to include('run_as' => 'image', 'capabilities' => %w[CHOWN SETUID])
      expect(response.body).to include('with these kernel permissions: CHOWN, SETUID')
    end

    it "takes a pasted app file as it is, pinning only its image line" do
      text = "# my app\nname: Mealie\ndescription: Recipes\ncategory: home\nimage: ghcr.io/mealie-recipes/mealie:v2.4.1\nrun_as: app\n"
      post '/apps/custom/review', params: { source: 'file', manifest: text }
      expect(Privileged.calls.last.last).to eq(app: 'mealie', manifest: text.sub('v2.4.1', "v2.4.1@#{digest}"))
    end

    it "goes back to the form with what's wrong" do
      allow_any_instance_of(AppVersions).to receive(:pin).and_raise(RuntimeError, 'ghcr.io has no mealie-recipes/meally')
      post '/apps/custom/review', params: { source: 'form', app: fields }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Couldn&#39;t find that image: ghcr.io has no mealie-recipes/meally", 'value="Mealie"')

      post '/apps/custom/review', params: { source: 'form', app: fields.merge(name: 'Jellyfin') }
      expect(response.body).to include('The Amahi-kai catalog has an app called jellyfin: give yours another name')
      post '/apps/custom/review', params: { source: 'form', app: fields.merge(name: '!!') }
      expect(response.body).to include('Give it a name, with letters')
      expect(Privileged.calls).to be_empty
    end

    # Its token goes on Private images, in a tab of its own, so the form is kept here
    it "offers to add a token for an image its registry says is private, on either tab" do
      allow_any_instance_of(AppVersions).to receive(:pin)
        .and_raise(AppVersions::Private.new('ghcr.io/catdogbark', "ghcr.io says catdogbark/bitshare is private, or isn't there"))
      post '/apps/custom/review', params: { source: 'form', app: fields.merge(image: 'ghcr.io/catdogbark/bitshare:0.3.0') }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("ghcr.io says catdogbark/bitshare is private, or isn&#39;t there. If it&#39;s private, the NAS needs a token for ghcr.io/catdogbark.",
                                       'href="/apps/private-images?owner=catdogbark&amp;registry=ghcr.io#add-token"', 'target="_blank"', 'Add a token for ghcr.io/catdogbark')
      post '/apps/custom/review', params: { source: 'file', manifest: file.sub(%r{image: .*}, 'image: ghcr.io/catdogbark/bitshare:0.3.0') }
      expect(response.body).to include("That doesn&#39;t work yet: Couldn&#39;t find that image: ghcr.io says catdogbark/bitshare is private")
      expect(response.body.scan('id="custom-add-token"').size).to eq(1)
    end

    it "says what the helper's checks found" do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('apps.custom_check', any_args)
                                         .and_raise(Privileged::Error.new('apps.custom_check', 'host port 445 must be from 1024 to 65535'))
      post '/apps/custom/review', params: { source: 'file', manifest: file.sub('host: 9925', 'host: 445') }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That doesn&#39;t work yet: host port 445 must be from 1024 to 65535", 'aria-selected="true" class="kai-custom-tab" data-custom-tab="file"')
    end

    it 'takes a picture for its logo with the form, shows it on the review, and gives it to the helper with the file' do
      post '/apps/custom/review', params: { source: 'form', app: fields, logo: picture(png.unpack1('m0')) }
      expect(response).to have_http_status(:ok)
      expect(Privileged.calls).to eq([['apps.custom_check', { app: 'mealie', manifest: file, logo: png }]])
      expect(response.body).to include(%(src="data:image/png;base64,#{png}"), %(name="logo_data" type="hidden" value="#{png}"))

      post '/apps/custom/add', params: { id: 'mealie', manifest: file, logo_data: png, password: 'secretpassword' }
      expect(Privileged.calls.last).to eq(['apps.custom_save', { app: 'mealie', manifest: file, logo: png }])
    end

    it "says what's wrong with a picture, beside its logo" do
      post '/apps/custom/review', params: { source: 'form', app: fields, logo: picture('GIF89a', 'logo.gif') }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('id="custom-logo-hint" role="alert">That isn&#39;t a PNG, JPEG, WebP or SVG picture')
      post '/apps/custom/review', params: { source: 'form', app: fields, logo: picture("\x89PNG\r\n\x1A\n#{'x' * 256 * 1024}".b) }
      expect(response.body).to include('That picture is over 256 KB: give it a smaller one')
      expect(Privileged.calls.map(&:first)).to eq(%w[apps.custom_check apps.custom_check]) # the file is still checked, without it

      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('apps.custom_check', hash_including(:logo))
                                         .and_raise(Privileged::Error.new('apps.custom_check', "the logo isn't a PNG, JPEG, WebP or SVG picture"))
      post '/apps/custom/review', params: { source: 'form', app: fields, logo: picture('<svg') }
      expect(response.body).to include('role="alert">The logo isn&#39;t a PNG, JPEG, WebP or SVG picture')
      expect(response.body).not_to include('name="logo_data"') # not carried on
    end

    it 'goes back from the review to the form with the picture chosen, to keep or remove' do
      post '/apps/custom/review', params: { back: '1', source: 'file', manifest: file, logo_data: png }
      expect(response.body).to include(%(src="data:image/png;base64,#{png}"), %(name="logo_data" type="hidden" value="#{png}"), 'Remove its logo')
    end

    it 'goes back from the review to the form, filled in as it was' do
      post '/apps/custom/review', params: { back: '1', source: 'file', id: 'mealie', manifest: file }
      expect(response.body).to include('value="Mealie"', 'value="ghcr.io/mealie-recipes/mealie:v2.4.1"', 'value="ALLOW_SIGNUP"', 'value="9925"')
      expect(Privileged.calls).to be_empty
    end

    it "asks for your password again before the helper keeps it, then opens Install" do
      post '/apps/custom/add', params: { id: 'mealie', manifest: file, password: 'wrong' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That isn&#39;t your password")
      expect(Privileged.calls).to be_empty

      post '/apps/custom/add', params: { id: 'mealie', manifest: file, password: 'secretpassword' }
      expect(Privileged.calls).to eq([['apps.custom_save', { app: 'mealie', manifest: file }]])
      expect(response).to redirect_to('/apps?install=mealie#docker_app_mealie')
    end

    it 'gives a few tries at the password a minute' do
      5.times { post '/apps/custom/add', params: { id: 'mealie', manifest: file, password: 'wrong' } }
      post '/apps/custom/add', params: { id: 'mealie', manifest: file, password: 'secretpassword' }
      expect(response).to redirect_to('/apps')
      expect(flash[:alert]).to start_with('Too many tries at your password')
      expect(Privileged.calls).to be_empty
    end

    it "doesn't add one over another of yours by the same name" do
      keep('mealie', file)
      post '/apps/custom/add', params: { id: 'mealie', manifest: file, password: 'secretpassword' }
      expect(response.body).to include('You have an app called mealie already')
      expect(Privileged.calls).to be_empty
    end
  end

  describe 'one of yours' do
    def installed(attrs = {})
      DockerApp.create!({ identifier: 'mealie', name: 'Mealie', image: pinned, status: 'running', host_port: 9925 }.merge(attrs))
    end

    def made_from(text)
      FileUtils.mkdir_p(definitions)
      File.write("#{definitions}/mealie.json", YAML.safe_load(text).to_json)
    end

    before { keep('mealie', file) }

    def logo(type, bytes)
      FileUtils.mkdir_p(custom)
      File.binwrite("#{custom}/mealie.#{type}", bytes)
      AppCatalog.reload!
    end

    it 'shows the logo kept on the NAS, never a link in its file' do
      keep('mealie', "#{file}logo: https://example.com/mealie.svg\n")
      installed(logo_url: 'https://example.com/mealie.svg')
      get '/apps'
      expect(response.body).not_to include('example.com/mealie.svg')
      logo('png', png.unpack1('m0'))
      version = Digest::SHA256.hexdigest(png.unpack1('m0'))[0, 12]
      get '/apps'
      expect(response.body).to include(%(src="/apps/logos/mealie?v=#{version}"))
      get '/apps/mealie'
      expect(response.body).to include(%(src="/apps/logos/mealie?v=#{version}"))
      get '/apps/custom/mealie/edit'
      expect(response.body).to include(%(src="/apps/logos/mealie?v=#{version}"), 'Remove its logo',
                                       'aria-selected="true" class="kai-custom-tab" data-custom-tab="form"') # the link is no matter
    end

    it 'serves its logo from the NAS under a policy that runs no script, cached by its address' do
      get '/apps/logos/mealie'
      expect(response).to have_http_status(:not_found)
      svg = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
      logo('svg', svg)
      get '/apps/logos/mealie', params: { v: Digest::SHA256.hexdigest(svg)[0, 12] }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/svg+xml')
      expect(response.body).to eq(svg)
      expect(response.headers['Content-Security-Policy']).to eq("default-src 'none'; img-src data:; style-src 'unsafe-inline'; sandbox")
      expect(response.headers['Cache-Control']).to include("max-age=#{1.year.to_i}", 'private')
      get '/apps/logos/mealie', params: { v: 'old' }
      expect(response.headers['Cache-Control']).to include('no-cache')
      get '/apps/logos/gitea' # a catalog app's: the catalog's, from the NAS too
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
    end

    it 'keeps its logo through an edit, unless another picture is chosen or Remove is' do
      post '/apps/custom/mealie/save', params: { manifest: file, password: 'secretpassword' }
      expect(Privileged.calls.last).to eq(['apps.custom_save', { app: 'mealie', manifest: file }])
      post '/apps/custom/mealie/save', params: { manifest: file, logo_remove: '1', password: 'secretpassword' }
      expect(Privileged.calls.last).to eq(['apps.custom_save', { app: 'mealie', manifest: file, logo: '' }])
      post '/apps/custom/mealie/save', params: { manifest: file, logo_data: png, password: 'secretpassword' }
      expect(Privileged.calls.last).to eq(['apps.custom_save', { app: 'mealie', manifest: file, logo: png }])
      post '/apps/custom/mealie/save', params: { manifest: file, logo_data: png, logo_remove: '1', password: 'secretpassword' }
      expect(Privileged.calls.last).to eq(['apps.custom_save', { app: 'mealie', manifest: file, logo: '' }]) # Remove, ticked last
    end

    it "saves a change to how it's listed alone without updating it, as the helper says" do
      installed
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('apps.custom_save', any_args).and_return('ok' => true, 'saved' => true, 'update' => false)
      post '/apps/custom/mealie/save', params: { manifest: file.sub('Recipes and meal plans', 'All our recipes'), logo_data: png, password: 'secretpassword' }
      expect(response).to redirect_to('/apps/mealie')
      expect(flash[:notice]).to eq("Mealie's changes are saved. They're only how it's listed, so it keeps running as it is.")
      expect(DockerApp.find_by(identifier: 'mealie').description).to eq('All our recipes')
    end

    # Its page lists the ports it was given at install, which a listing-only save doesn't touch
    it "gives its page a port's new label when that's all that changed" do
      installed(ports: [{ host: 9925, container: 9000, protocol: 'tcp', label: 'web' }, { host: 8554, container: 8554, protocol: 'tcp' }])
      two = "ports:\n- host: 9925\n  container: 9000\n- host: 8554\n  container: 8554\n"
      keep('mealie', file.sub("ports:\n- host: 9925\n  container: 9000\n", two))
      labelled = file.sub("ports:\n- host: 9925\n  container: 9000\n", "#{two}  label: RTSP\n")
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('apps.custom_save', any_args) do
        keep('mealie', labelled) # as the helper writes it
        { 'ok' => true, 'saved' => true, 'update' => false }
      end
      post '/apps/custom/mealie/save', params: { manifest: labelled, password: 'secretpassword' }
      expect(response).to redirect_to('/apps/mealie')
      expect(DockerApp.find_by(identifier: 'mealie').port_summary).to eq('9925 (web) · 8554 (RTSP)')
    end

    it 'says "web" for its web page\'s port, in place of a label, and a label is optional' do
      get '/apps/custom/mealie/edit'
      row = Nokogiri::HTML(response.body).at_css('[data-custom-rows="ports"] [data-custom-row]')
      expect(row.at_css('[data-custom-port-label]')).to have_attributes(attributes: include('hidden'))
      expect(row.at_css('[data-custom-port-label]')['placeholder']).to eq('Optional')
      expect(row.at_css('[data-custom-port-web]').attributes).not_to include('hidden')
      expect(row.at_css('[data-custom-port-web]').text).to eq('web')
    end

    it 'opens Edit on the form, filled in, or on its file when it says more than the form shows' do
      get '/apps/custom/mealie/edit'
      expect(response.body).to include('Edit Mealie', 'value="Mealie"', 'value="SECRET_KEY"', 'name="editing" type="hidden" value="mealie"',
                                       'aria-selected="true" class="kai-custom-tab" data-custom-tab="form"')
      keep('mealie', "#{file}ping: /bin/ping\n")
      get '/apps/custom/mealie/edit'
      expect(response.body).to include('aria-selected="true" class="kai-custom-tab" data-custom-tab="file"', 'ping: /bin/ping')
    end

    it 'saves the changes with your password, then its page updates it to them' do
      installed
      made_from(file)
      changed = file.sub('Recipes and meal plans', 'All our recipes')
      post '/apps/custom/mealie/save', params: { manifest: changed, password: 'secretpassword' }
      expect(Privileged.calls).to eq([['apps.custom_save', { app: 'mealie', manifest: changed }]])
      expect(response).to redirect_to('/apps/mealie?apply=1')
      expect(DockerApp.find_by(identifier: 'mealie').description).to eq('All our recipes')

      keep('mealie', changed)
      get '/apps/mealie', params: { apply: 1 }
      expect(response.body).to include('Custom', "Your changes aren't in it yet", 'Apply them')
      expect(response.body).to match(%r{data-app-stream="mealie" data-auto-open="" data-title="Updating Mealie..." data-url="/apps/docker/update_stream/mealie"})
      get '/apps/mealie'
      expect(response.body).not_to include('data-auto-open')
    end

    it "says so when the changes name an older version, which it isn't updated to" do
      installed
      post '/apps/custom/mealie/save', params: { manifest: file.sub('v2.4.1@', 'v2.3.0@'), password: 'secretpassword' }
      expect(response).to redirect_to('/apps/mealie')
      expect(flash[:alert]).to include('v2.3.0 is older than the v2.4.1 it runs')
    end

    it "says nothing's waiting once its container runs the file" do
      installed
      made_from(file)
      get '/apps/mealie', params: { apply: 1 }
      expect(response.body).not_to include("Your changes aren't in it yet")
      expect(response.body).not_to include('data-auto-open')
      expect(response.body).to include('Check for a newer version', 'href="/apps/custom/mealie/edit"')
    end

    it 'finds a newer version only when asked, and updates to it without the password' do
      installed
      made_from(file)
      newer = AppVersions::Result.new(kind: :newer, latest: 'v2.5.0', image: "ghcr.io/mealie-recipes/mealie:v2.5.0@sha256:#{'b' * 64}", major: false)
      allow_any_instance_of(AppVersions).to receive(:check_image).and_return(newer)
      post '/apps/custom/mealie/check'
      expect(response).to redirect_to('/apps/mealie#app-version-mealie')
      follow_redirect!
      expect(response.body).to include('v2.5.0 is out, from the same image.', 'Update to v2.5.0', 'action="/apps/custom/mealie/version"')
      expect(response.body).not_to include('flash-data') # what it found is on the page, not a toast

      post '/apps/custom/mealie/version', params: { tag: 'v2.5.0' }
      expect(saved_manifest).to eq(file.sub(pinned, newer.image))
      expect(response).to redirect_to('/apps/mealie?apply=1')
    end

    it 'points to Private images when its image turns out private' do
      installed
      allow_any_instance_of(AppVersions).to receive(:check_image)
        .and_raise(AppVersions::Private.new('ghcr.io/mealie-recipes', "ghcr.io says mealie-recipes/mealie is private, or isn't there"))
      post '/apps/custom/mealie/check'
      expect(flash[:alert]).to eq("Couldn't ask its registry for a newer version: ghcr.io says mealie-recipes/mealie is private, or isn't there. " \
                                  'If it\'s private, add a token for ghcr.io/mealie-recipes on Private images (under Apps).')
    end

    it "doesn't update to a tag that isn't the newest any more" do
      allow_any_instance_of(AppVersions).to receive(:check_image).and_return(AppVersions::Result.new(kind: :current, latest: 'v2.4.1'))
      post '/apps/custom/mealie/version', params: { tag: 'v1.0.0' }
      expect(flash[:alert]).to include("isn't the newest version any more")
      expect(Privileged.calls).to be_empty
    end

    it 'removes it through the helper' do
      post '/apps/custom/mealie/remove'
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(Privileged.calls).to eq([['apps.custom_remove', { app: 'mealie' }]])
    end

    it "isn't one of yours when it's the catalog's" do
      get '/apps/custom/gitea/edit'
      expect(response).to redirect_to('/apps')
    end
  end
end

require 'rails_helper'

# Apps of the owner's own (the root helper's custom.rb): an app file kept on this NAS only, after
# the catalog's checks, in an id nothing else has had, and installed from there.
RSpec.describe 'AmahiHelper custom apps' do
  let(:helper) { AmahiHelper }
  let(:dir) { Dir.mktmpdir }
  let(:custom) { "#{dir}/custom-apps" }
  let(:digest) { "sha256:#{'a' * 64}" }
  let(:file) do
    <<~YAML
      name: Mealie
      description: Recipes and meal plans
      category: home
      image: ghcr.io/mealie-recipes/mealie:v2.4.1@#{digest}
      run_as: app
      web_port: 9925
      ports:
        - { host: 9925, container: 9000 }
      folders:
        - { name: data, path: /app/data }
      environment:
        TZ: "{{timezone}}"
      secrets:
        - { env: SECRET_KEY, label: Secret key }
    YAML
  end

  # A 1x1 PNG, and an SVG with all an editor puts before its <svg>
  let(:png) { 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=' }
  let(:svg) do
    <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <!-- Made in an editor -->
      <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 5 5"><rect width="5" height="5" fill="#ff0055"/></svg>
    SVG
  end

  before(:all) { Privileged.operations } # loads the helper's source once

  before do
    stub_const('AmahiHelper::APP_CUSTOM', custom)
    stub_const('AmahiHelper::APP_MANIFESTS', Rails.root.join('config/apps').to_s)
    stub_const('AmahiHelper::APP_CATALOG', "#{dir}/catalog")
    stub_const('AmahiHelper::APPS_ROOT', "#{dir}/apps")
    stub_const('AmahiHelper::APP_SECRETS', "#{dir}/app-secrets")
    stub_const('AmahiHelper::APP_DEFINITIONS', "#{dir}/app-definitions")
    stub_const('AmahiHelper::APP_STORAGE', "#{dir}/app-storage.json")
    allow(helper).to receive(:app_job_running?).and_return(false)
    allow(helper).to receive(:engine_installed?).and_return(true)
    allow(helper).to receive(:engine_container?).and_return(false)
    allow(helper).to receive(:passwd).and_return(nil)
    allow(helper).to receive(:group_id).and_call_original
    allow(helper).to receive(:group_id).with('amahi').and_return(Process.gid)
    allow(File).to receive(:chown)
    allow(helper).to receive(:do_install) { |path, content, *| File.binwrite(path, content) }
  end

  after { FileUtils.rm_rf(dir) }

  def refusal(op, args)
    helper.validate(op, args)
    nil
  rescue AmahiHelper::Refused => e
    e.message
  end

  def run(op, args)
    values = helper.validate(op, args)
    helper.plan(op, values).map { |step| helper.send("do_#{step.first}", *step.drop(1)) }.last
  end

  it 'checks a file with the checks a catalog manifest gets, and saves nothing' do
    expect(run('apps.custom_check', 'app' => 'mealie', 'manifest' => file)).to eq('app' => 'mealie', 'checked' => true)
    expect(Dir.exist?(custom)).to be false
  end

  it "keeps a file that passes as the app's, for the web app's group to read" do
    expect(run('apps.custom_save', 'app' => 'mealie', 'manifest' => file.chomp)).to eq('app' => 'mealie', 'saved' => true, 'update' => false)
    expect(File.read("#{custom}/mealie.yml")).to eq(file)
    expect(File.stat(custom).mode & 0o777).to eq(0o750)
    expect(File).to have_received(:chown).with(0, Process.gid, custom)
    expect(helper).to have_received(:do_install).with("#{custom}/mealie.yml", file, nil, '0640', 'amahi')
  end

  it 'keeps its logo beside its file, for the web app to serve, and changes or removes it only when asked' do
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file, 'logo' => png)
    expect(File.binread("#{custom}/mealie.png")).to eq(png.unpack1('m0'))
    expect(helper).to have_received(:do_install).with("#{custom}/mealie.png", png.unpack1('m0'), nil, '0640', 'amahi')
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file.sub('Recipes', 'All the recipes'))
    expect(Dir.children(custom)).to contain_exactly('mealie.yml', 'mealie.png') # left out: kept
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file, 'logo' => [svg].pack('m0'))
    expect(Dir.children(custom)).to contain_exactly('mealie.yml', 'mealie.svg') # another type: the other goes
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file, 'logo' => '')
    expect(Dir.children(custom)).to contain_exactly('mealie.yml')
  end

  it "refuses a logo that isn't a PNG, JPEG, WebP or SVG of 256 KB at most" do
    check = ->(logo) { refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => file, 'logo' => logo) }
    expect(check.call(png)).to be_nil
    expect(check.call([svg].pack('m0'))).to be_nil
    expect(check.call(["\xFF\xD8\xFF\xE0rest".b].pack('m0'))).to be_nil
    expect(check.call(["RIFF\x10\0\0\0WEBPVP8 ".b].pack('m0'))).to be_nil
    expect(check.call("#{png}\n")).to eq('the logo must be a picture, in base64')
    expect(check.call('not base64!')).to eq('the logo must be a picture, in base64')
    expect(check.call(1)).to eq('the logo must be a picture, in base64')
    expect(check.call(['GIF89a'].pack('m0'))).to eq("the logo isn't a PNG, JPEG, WebP or SVG picture")
    expect(check.call(['<html><svg></svg></html>'].pack('m0'))).to eq("the logo isn't a PNG, JPEG, WebP or SVG picture")
    expect(check.call(['<!DOCTYPE svg [<!ENTITY a "aaaa">]><svg>&a;</svg>'].pack('m0'))).to eq("the logo isn't a PNG, JPEG, WebP or SVG picture")
    expect(check.call(['<!-- never closed <svg></svg>'].pack('m0'))).to eq("the logo isn't a PNG, JPEG, WebP or SVG picture")
    expect(check.call(["<svg>\0</svg>"].pack('m0'))).to eq("the logo isn't a PNG, JPEG, WebP or SVG picture")
    expect(check.call(["\x89PNG\r\n\x1A\n#{'x' * 256 * 1024}".b].pack('m0'))).to eq('the logo is over 256 KB')
  end

  # Its name, how it's listed, and a field written out as its default: the same container
  it "records a change its container doesn't see as what the container was made from, so it needs no update" do
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file)
    allow(helper).to receive(:engine_container?).and_return(true)
    FileUtils.mkdir_p("#{dir}/app-definitions")
    File.write("#{dir}/app-definitions/mealie.json", YAML.safe_load(file).to_json)
    listed = file.sub('Recipes', 'All the recipes').sub('category: home', "category: other\nsign_in: Make an account\nmemory: 1g\nnetwork: internet")
    expect(run('apps.custom_save', 'app' => 'mealie', 'manifest' => listed)).to include('update' => false)
    expect(JSON.parse(File.read("#{dir}/app-definitions/mealie.json"))).to include('description' => 'All the recipes and meal plans', 'memory' => '1g')

    moved = listed.sub('host: 9925, container: 9000', 'host: 9926, container: 9000').sub('web_port: 9925', 'web_port: 9926')
    expect(run('apps.custom_save', 'app' => 'mealie', 'manifest' => moved)).to include('update' => true)
    expect(JSON.parse(File.read("#{dir}/app-definitions/mealie.json"))['web_port']).to eq(9925) # until the update runs
  end

  it "says what's wrong with a file, in the owner's words, as a refusal" do
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => file.sub("@#{digest}", ''))).to eq('image must be name:tag@sha256:digest')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => file.sub('host: 9925', 'host: 445'))).to eq('host port 445 must be from 1024 to 65535')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "#{file}privileged: true\ncap_add: [SYS_ADMIN]\n")).to be_nil # nothing reads them
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "#{file}capabilities: [SYS_ADMIN]\n")).to start_with('capabilities must be a list')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => file.sub('/app/data', '/etc'))).to be_nil
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => file.sub('/app/data', '/shares/x'))).to eq('folder path /shares/x is where the shares go')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => file.sub('name: Mealie', 'name: "Two\nlines"'))).to eq('name must be one line of text')
    on_pool = file.sub('path: /app/data }', 'path: /app/data, kind: dataset }')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "requires: 3\n#{on_pool}")).to be_nil
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "requires: 3\n#{on_pool.sub('run_as: app', 'run_as: image')}"))
      .to eq('an app that starts as root (run_as: image) keeps its folders on the system disk, not a ZFS pool (kind: dataset)')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "requires: 6\n#{file}")).to eq('it needs a newer Amahi-kai (requires: 6): run System Update first')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "- just\n- a list\n")).to start_with("it isn't an app file")
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "name: &a [*a]\n")).to start_with("it can't be read as YAML")
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => "#{file}# #{'x' * 70_000}")).to eq('the app file is over 64 KB')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => 1)).to eq('the app file must be text')
  end

  it "refuses an id the catalog has, or one an app on this NAS had, so it takes over nobody's data" do
    expect(refusal('apps.custom_save', 'app' => 'jellyfin', 'manifest' => file)).to eq('the Amahi-kai catalog has an app called jellyfin: give yours another name')
    FileUtils.mkdir_p("#{dir}/catalog/apps")
    File.write("#{dir}/catalog/apps/mealie.yml", 'name: Mealie')
    expect(refusal('apps.custom_save', 'app' => 'mealie', 'manifest' => file)).to start_with('the Amahi-kai catalog has an app called mealie')
    FileUtils.rm_rf("#{dir}/catalog")

    taken = [-> { allow(helper).to receive(:engine_container?).with('amahi-mealie').and_return(true) },
             -> { FileUtils.mkdir_p("#{dir}/apps/mealie") },
             -> { FileUtils.mkdir_p("#{dir}/app-definitions") && File.write("#{dir}/app-definitions/mealie.json", '{}') },
             -> { FileUtils.mkdir_p("#{dir}/app-secrets") && File.write("#{dir}/app-secrets/mealie.json", '{}') },
             -> { File.write("#{dir}/app-storage.json", '{"mealie":"tank"}') },
             -> { allow(helper).to receive(:passwd).with('app-mealie').and_return(Etc::Passwd.new('app-mealie')) }]
    taken.each do |take|
      take.call
      expect(refusal('apps.custom_save', 'app' => 'mealie', 'manifest' => file)).to start_with('an app called mealie was installed on this NAS')
      allow(helper).to receive(:engine_container?).and_return(false)
      allow(helper).to receive(:passwd).and_return(nil)
      FileUtils.rm_rf(["#{dir}/apps", "#{dir}/app-definitions", "#{dir}/app-secrets", "#{dir}/app-storage.json"])
    end
    expect(refusal('apps.custom_save', 'app' => 'mealie', 'manifest' => file)).to be_nil
  end

  it 'changes an app of your own whatever else its id has now: its container, data, or the catalog adding it' do
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file)
    allow(helper).to receive(:engine_container?).and_return(true)
    FileUtils.mkdir_p(["#{dir}/apps/mealie", "#{dir}/catalog/apps"])
    File.write("#{dir}/catalog/apps/mealie.yml", 'name: Mealie')
    expect(refusal('apps.custom_save', 'app' => 'mealie', 'manifest' => file.sub('Recipes', 'All the recipes'))).to be_nil
  end

  it "refuses a change while the app's job runs" do
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file)
    allow(helper).to receive(:app_job_running?).with('mealie').and_return(true)
    expect(refusal('apps.custom_save', 'app' => 'mealie', 'manifest' => file)).to start_with('mealie is being changed')
    expect(refusal('apps.custom_check', 'app' => 'mealie', 'manifest' => file)).to be_nil
  end

  it 'installs an app of your own from its file, which comes before the catalog' do
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file)
    expect(helper.app_manifest_path('mealie')).to eq("#{custom}/mealie.yml")
    expect(helper.app_manifest('mealie')).to include(image: "ghcr.io/mealie-recipes/mealie:v2.4.1@#{digest}", run_as: 'app', capabilities: nil)
    expect(helper.app_capabilities('mealie', helper.app_manifest('mealie'))).to eq([])
    expect(helper.app_manifest_path('jellyfin')).to eq(Rails.root.join('config/apps/jellyfin.yml').to_s)
  end

  it "forgets one that isn't installed and has no data kept, and only one of your own" do
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file)
    allow(helper).to receive(:engine_container?).with('amahi-mealie').and_return(true)
    expect(refusal('apps.custom_remove', 'app' => 'mealie')).to eq('mealie is installed: uninstall it first')
    allow(helper).to receive(:engine_container?).and_return(false)
    FileUtils.mkdir_p("#{dir}/apps/mealie")
    expect(refusal('apps.custom_remove', 'app' => 'mealie')).to eq("mealie's data from an earlier install is kept: delete it first")
    FileUtils.rm_rf("#{dir}/apps")
    expect(refusal('apps.custom_remove', 'app' => 'jellyfin')).to eq("jellyfin isn't an app of your own")
    run('apps.custom_save', 'app' => 'mealie', 'manifest' => file, 'logo' => png)
    expect(run('apps.custom_remove', 'app' => 'mealie')).to eq('app' => 'mealie', 'removed' => true)
    expect(Dir.children(custom)).to be_empty
  end
end

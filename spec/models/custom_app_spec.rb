require 'spec_helper'

# An app of your own's file (CustomApp), made from the Add your own app form or pasted. The root
# helper checks it (amahi_helper_custom_spec.rb); this makes it, reads it back, and says it.
describe CustomApp do
  let(:form) do
    { 'name' => 'Home Box', 'description' => 'A box', 'category' => 'home', 'image' => 'ghcr.io/me/box:1.0', 'run_as' => 'app',
      'network' => 'lan', 'memory' => '2g', 'web' => 'b', 'shares' => '1',
      'ports' => { 'a' => { 'host' => '9001', 'container' => '53', 'protocol' => 'udp' }, 'b' => { 'host' => '9000', 'container' => '80' },
                   'c' => { 'host' => '', 'container' => '' } },
      'folders' => { 'a' => { 'name' => 'data', 'path' => '/data' }, 'b' => { 'name' => '', 'path' => '' } },
      'settings' => { 'a' => { 'name' => 'TZ', 'kind' => 'timezone' }, 'b' => { 'name' => 'PUID', 'kind' => 'uid', 'value' => 'ignored' },
                      'c' => { 'name' => 'Media-folder', 'kind' => 'value', 'value' => '/shares' } },
      'secrets' => { 'a' => { 'name' => 'API_KEY', 'label' => '' } }, 'capabilities' => ['', 'CHOWN'] }
  end

  it 'makes an app file from the form, in the catalog\'s order, leaving out empty rows' do
    app = described_class.from_form(form)
    expect(app.id).to eq('homebox')
    expect(app.data).to eq(
      'requires' => 4, 'name' => 'Home Box', 'description' => 'A box', 'category' => 'home', 'image' => 'ghcr.io/me/box:1.0',
      'run_as' => 'app', 'network' => 'lan', 'memory' => '2g', 'web_port' => 9000,
      'ports' => [{ 'host' => 9001, 'container' => 53, 'protocol' => 'udp' }, { 'host' => 9000, 'container' => 80 }],
      'folders' => [{ 'name' => 'data', 'path' => '/data' }], 'shares' => true,
      'environment' => { 'TZ' => '{{timezone}}', 'PUID' => '{{uid}}', 'Media-folder' => '/shares' },
      'secrets' => [{ 'env' => 'API_KEY', 'label' => 'Api key' }]
    )
    expect(app.text).to start_with("requires: 4\nname: Home Box\n")
  end

  it "gives capabilities only to an app that runs as the image says, and leaves what isn't a number for the helper to refuse" do
    app = described_class.from_form(form.merge('run_as' => 'image', 'ports' => { 'a' => { 'host' => 'eighty', 'container' => '80' } }))
    expect(app.data).to include('run_as' => 'image', 'capabilities' => ['CHOWN'], 'ports' => [{ 'host' => 'eighty', 'container' => 80 }])
    expect(app.data).not_to have_key('web_port')
  end

  it 'reads its file back into the form, or leaves it to the file when the form can\'t show it' do
    app = described_class.from_file(described_class.from_form(form).text, id: 'homebox')
    expect(app.form).to include('name' => 'Home Box', 'run_as' => 'app', 'network' => 'lan', 'memory' => '2g', 'web' => '1', 'shares' => '1',
                                'settings' => { '0' => { 'name' => 'TZ', 'kind' => 'timezone', 'value' => '' },
                                                '1' => { 'name' => 'PUID', 'kind' => 'uid', 'value' => '' },
                                                '2' => { 'name' => 'Media-folder', 'kind' => 'value', 'value' => '/shares' } })
    expect(described_class.from_file("name: X\nimage: a/b:1\naccess: tailscale\n").form).to be_nil
    expect(described_class.from_file("name: X\nfolders:\n  - { name: d, path: /d, kind: dataset }\n").form).to be_nil
  end

  # A logo link is no matter: its logo is a picture kept on the NAS
  it 'opens a file with a logo link on the form, which leaves the link out' do
    app = described_class.from_file("name: X\nimage: a/b:1\nrun_as: app\nlogo: https://example.com/x.svg\n")
    expect(app.form).to include('name' => 'X')
    expect(described_class.from_form(app.form).data).not_to have_key('logo')
  end

  it "tells a logo's type by its first bytes, for the pages to show it" do
    expect(described_class.logo_type("\x89PNG\r\n\x1A\nrest".b)).to eq('image/png')
    expect(described_class.logo_type("\xFF\xD8\xFF\xE0".b)).to eq('image/jpeg')
    expect(described_class.logo_type("RIFF\0\0\0\0WEBPVP8 ".b)).to eq('image/webp')
    expect(described_class.logo_type('<?xml version="1.0"?><svg/>')).to eq('image/svg+xml')
    expect(described_class.logo_type('GIF89a')).to be_nil
    expect(described_class.logo_type("\xFF\xFE<svg".b)).to be_nil
  end

  it 'pins a pasted file by its image line only, keeping the rest as it was written' do
    app = described_class.from_file("# mine\nname: Box\nimage: 'ghcr.io/me/box:1.0'   \nrun_as: app\n")
    expect(app.id).to eq('box')
    app.pin("ghcr.io/me/box:1.0@sha256:#{'a' * 64}")
    expect(app.text).to eq("# mine\nname: Box\nimage: ghcr.io/me/box:1.0@sha256:#{'a' * 64}\nrun_as: app\n")
    expect(app.image_parts).to eq(['ghcr.io/me/box:1.0', 'aaaa…aaaa'])
  end

  it "says what's wrong with a file that isn't one" do
    expect(described_class.from_file('').errors[:file]).to eq('Paste the app file first')
    expect(described_class.from_file("- a\n").errors[:file]).to start_with("It isn't an app file")
    expect(described_class.from_file("name: [\n").errors[:file]).to start_with("It can't be read as YAML")
  end

  it "says what it will be able to do, with this NAS's processors" do
    allow(Etc).to receive(:nprocessors).and_return(4)
    facts = described_class.from_form(form.merge('run_as' => 'image')).facts.to_h
    expect(facts).to include('Runs' => 'As the image says (often root, switching to its own user), with these kernel permissions: CHOWN',
                             'Reaches' => 'Reaches the internet and the devices on your network',
                             'Reached at' => 'Ports 9001/udp and 9000 (its web page), from your network and Tailscale only',
                             'Your shares' => 'The ones you choose at install, read only',
                             'Limits' => "Up to 2 GB of memory, and 3 of the NAS's 4 processors")
    allow(Etc).to receive(:nprocessors).and_return(1)
    expect(described_class.processors).to eq("the NAS's one processor")
  end
end

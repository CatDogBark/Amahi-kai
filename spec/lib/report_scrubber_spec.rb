require 'rails_helper'

# Taking the names and addresses out of a problem's report (ReportScrubber): stand-ins like
# <share-1>, the same name always the same one, and what's needed to find the fault left in.
RSpec.describe ReportScrubber do
  let(:names) do
    { 'server-name' => ['nas'], 'user' => %w[troy Rhonda], 'share' => %w[Vault vault-old], 'pool' => ['data'],
      'device' => %w[carport-cam linksys] }
  end
  let(:scrubber) { described_class.new(names) }

  it "takes out this server's name, its users, shares, pools and devices, in any case, as whole words" do
    expect(scrubber.scrub('nas: troy shared Vault and vault-old on pool data; carport-cam and Linksys answered; RHONDA too'))
      .to eq('<server-name>: <user-1> shared <share-1> and <share-2> on pool <pool-1>; <device-1> and <device-2> answered; <user-2> too')
    expect(scrubber.scrub('database canvas metadata troyes')).to eq('database canvas metadata troyes') # inside other words: kept
  end

  it 'gives the same name the same stand-in everywhere in a report' do
    expect(scrubber.scrub("Vault at 192.168.1.20\nvault again, 192.168.1.20, then 192.168.1.21"))
      .to eq("<share-1> at <lan-address-1>\n<share-1> again, <lan-address-1>, then <lan-address-2>")
  end

  it 'takes out addresses, keeping loopback, any-address and masks, and times' do
    text = 'LAN 10.99.0.60 WAN 66.8.144.62 lo 127.0.0.1 on 0.0.0.0/255.255.255.0 at 03:41:06.123 and 2026-10-29T03:41:06Z'
    expect(scrubber.scrub(text))
      .to eq('LAN <lan-address-1> WAN <address-1> lo 127.0.0.1 on 0.0.0.0/255.255.255.0 at 03:41:06.123 and 2026-10-29T03:41:06Z')
    expect(scrubber.scrub('ULA fd4f:6682:2e09::53, link fe80::8269:1aff:fe0a:1384%ens18, ::1, MAC D0:3F:27:4A:93:1D'))
      .to eq('ULA <ipv6-address-1>, link <ipv6-address-2>%ens18, ::1, MAC <mac-1>')
  end

  # On a real install, every line of Amahi-kai's log starts with its request's id, and a long path
  # was taken for a key
  it "keeps request ids and paths, which name no one" do
    line = 'I, [2026-10-29T22:54:18.916876 #3820]  INFO -- : [0f8fad5b-d9cb-469f-a165-70867728950e] Started GET ' \
           '"/settings/help/log?source=journal" from /opt/amahi-kai/app/controllers/settings_controller_with_a_long_name2026.rb'
    expect(scrubber.scrub(line)).to eq(line)
  end

  # sshd logs each login's key by its fingerprint: base64, where an image digest is hex
  it "takes out an SSH key's fingerprint whole" do
    expect(scrubber.scrub('Accepted publickey for troy from 192.168.1.169 port 45426 ssh2: ED25519 SHA256:JcOwwz/abc+def123GHI456jkl789MNO012pqr345ST'))
      .to eq('Accepted publickey for <user-1> from <lan-address-1> port 45426 ssh2: ED25519 SHA256:<key-fingerprint>')
  end

  # A release key's line in /etc/amahi-kai/allowed_signers, say, quoted in a report: base64 with
  # slashes, which the secret rule stopped at, so half the key stayed
  it "takes out SSH public keys whole, keeping a release key's name" do
    expect(scrubber.scrub('release-key-a namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyX9/OnlyForTheSpec+NotReal0123456'))
      .to eq('release-key-a namespaces="git" ssh-ed25519 <ssh-key>')
    expect(scrubber.scrub('ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7fake/key+text= troy@laptop; MD5:3b:8e:01:2a:44:9c:d0:11:5e:6f:70:81:92:a3:b4:c5'))
      .to eq('ssh-rsa <ssh-key> <user-1>@laptop; MD5:<key-fingerprint>')
  end

  it 'takes out armoured key text: a signature or a private key, whole or with its end cut off' do
    signed = "tag v1.5.1\n\nv1.5.1 — signed releases\n-----BEGIN SSH SIGNATURE-----\n" \
             "U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgFakeSignatureTextForTheSpecOnly0123456789ab\n" \
             "Zm9vYmFy+/xyz=\n-----END SSH SIGNATURE-----\n2026-10-30T01:02:03Z next line"
    expect(scrubber.scrub(signed))
      .to eq("tag v1.5.1\n\nv1.5.1 — signed releases\n-----BEGIN SSH SIGNATURE----- <key-text> -----END SSH SIGNATURE-----\n2026-10-30T01:02:03Z next line")
    cut = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ=\n2026-10-30T01:02:03Z helper: next"
    expect(scrubber.scrub(cut)).to eq("-----BEGIN OPENSSH PRIVATE KEY----- <key-text>\n2026-10-30T01:02:03Z helper: next")
    journal = 'Oct 30 01:02:03 nas app[12]: U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgFake/SignatureText+ForTheSpec01'
    expect(scrubber.scrub(journal)).to eq('Oct 30 01:02:03 <server-name> app[12]: <key-text>')
    path = '/srv/pools/data/media/Pictures/2024/Rhonda/ChristmasMorning/IMG20241225Tree/Family'
    expect(scrubber.scrub(path)).not_to include('<key-text>') # a path, even a long one, isn't key text
  end

  it 'takes out email addresses, tailnet names and keys, keeping commit and image hashes' do
    text = 'mail catdogbark@pm.me; serve amahi-kai.tail1234.ts.net; ADMIN_TOKEN=Kq8sD9fL2mN4pR7tV1wX3yZ5aB6cE0gH; ' \
           "commit 82767a8a1b2c3d4e5f60718293a4b5c6d7e8f901, image sha256:#{'4813745e' * 8}"
    expect(scrubber.scrub(text)).to eq("mail <email-1>; serve <tailnet-name-1>; ADMIN_TOKEN=<secret>; commit 82767a8a1b2c3d4e5f60718293a4b5c6d7e8f901, image sha256:#{'4813745e' * 8}")
  end

  it "takes out the folders and files in a share, wherever its path is written, and a share it doesn't know" do
    text = <<~TEXT
      setfacl: /srv/pools/data/shares/vault/Downloads/complete/movie.mkv: Operation not supported
      Couldn't create /shares/Vault/Downloads/complete: Permission denied
      apps.install app=transmission shares=[Vault/Downloads rw]
      gone: /var/lib/amahi-kai/files/oldstuff/a.txt
    TEXT
    expect(scrubber.scrub(text)).to eq(<<~TEXT)
      setfacl: /srv/pools/<pool-1>/shares/<share-1>/<folder-1>/<folder-2>/<file-1>: Operation not supported
      Couldn't create /shares/<share-1>/<folder-1>/<folder-2>: Permission denied
      apps.install app=transmission shares=[<share-1>/<folder-1> rw]
      gone: /var/lib/amahi-kai/files/<share-2>/<file-2>
    TEXT
  end

  it "reads the NAS's own names, the longest first, leaving out ones too short to tell" do
    create(:share, name: 'Vault', path: '/srv/pools/data/shares/vault')
    create(:share, name: 'TV', path: '/var/lib/amahi-kai/files/tv')
    Host.create!(name: 'carport-cam', mac: 'aa:bb:cc:dd:ee:01')
    allow(SystemInfo).to receive(:hostname).and_return('nas')
    allow(StoragePools).to receive(:status).and_return(pools: [StoragePools::Pool.new(name: 'data', managed: true)], offline: [], found: [])
    # The server's own accounts, the journal names them (ssh, sudo); system and service ones aren't people
    accounts = [Etc::Passwd.new('root', 'x', 0), Etc::Passwd.new('amahi', 'x', 998), Etc::Passwd.new('troy', 'x', 1000),
                Etc::Passwd.new('nobody', 'x', 65_534)]
    allow(Etc).to receive(:passwd) { |&block| accounts.each(&block) }
    found = described_class.names
    expect(found['user']).to include('troy')
    expect(found['user']).not_to include('root', 'amahi', 'nobody')
    expect(found['share']).to eq(['Vault', 'vault']) # TV and tv: too short to take out without taking out other words
    expect(found['pool']).to eq(['data'])
    expect(found['device']).to include('carport-cam')
    expect(found['server-name']).to eq(['nas'])
  end
end

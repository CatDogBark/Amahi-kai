require 'etc'
require 'ipaddr'

# Takes the names and addresses out of a problem's report (Settings → Help → Report a problem):
# each becomes a stand-in like <share-1>, and the same name gets the same stand-in everywhere in
# the report, so it still reads as one story. Out: this server's name, users, shares and what's in
# them, the server's accounts, ZFS pools, devices' and DNS names, addresses (IPv4, IPv6, MAC),
# email addresses, a tailnet's names, SSH keys' fingerprints and public keys, armoured key text (a
# private key, a release tag's signature), and anything that looks like a key or token. Kept: a
# release key's name (release-key-a, as config/allowed_signers has it), and what's needed to find the
# fault (versions, commit and image hashes, loopback addresses, times, the apps' names).
class ReportScrubber
  MAC = /\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b/i
  IPV4 = /\b(?:\d{1,3}\.){3}\d{1,3}\b/
  # A word with colons that IPAddr reads as IPv6; times (03:41:06) don't have the hex or the colons.
  IPV6 = /(?<![\w:])(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(?![\w:])/i
  EMAIL = /\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b/
  TAILNET = /\b[\w-]+(?:\.[\w-]+)*\.ts\.net\b/i
  # 32 or more letters and digits with both in it (base64's = padding after): a key, a token, a
  # password Amahi-kai made, not the setting's name before it nor a path's part. A git commit (40
  # hex), an image digest (64 hex) or an id (a UUID) stays.
  SECRET = /(?<![\w:\/])(?=[A-Za-z0-9_\-+]{32,})(?=[^\s=\/]*[A-Za-z])(?=[^\s=\/]*\d)[A-Za-z0-9_\-+]{32,}={0,2}/
  HEX_HASH = /\A(?:\h{40}|\h{64})\z/
  # A request's or a job's id, which ties a report's lines together and names no one.
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  # An SSH key's fingerprint (sshd logs the key each login used); an image digest is sha256: in hex.
  KEY_FINGERPRINT = %r{\bSHA256:[A-Za-z0-9+/]{40,}=*}
  MD5_FINGERPRINT = /\bMD5:(?:\h{2}:){15}\h{2}\b/
  # An SSH public key, as an allowed_signers, authorized_keys or known_hosts line has it. Its base64
  # has slashes, where SECRET stops, so half of it stayed.
  SSH_PUBLIC_KEY = %r{\b(ssh-(?:ed25519|rsa|dss)|ecdsa-sha2-nistp\d{3}|sk-(?:ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com) [A-Za-z0-9+/]{16,}={0,3}}
  # Armoured key text: a private key, an SSH signature (a signed tag holds one), PGP. Its lines up
  # to the END line, or to the first line that isn't key text, when a log's cut left the end off.
  ARMOR = %r{-----BEGIN ([A-Z0-9 ]{1,40})-----(?:[ \t]*\n(?:[A-Za-z0-9+/=]+|(?:Version|Comment|Hash|Charset): [^\n]*)?(?=[ \t]*(?:\n|\z)))*(?:[ \t]*\n[ \t]*-----END \1-----)?}
  # Key text in a line that starts with something else (a journal line's prefix): 60 or more base64
  # characters with a slash or a plus, a digit and both cases. Not a path, which starts with a slash.
  BASE64_RUN = %r{(?<![\w/+.\-])(?!/)(?=[A-Za-z0-9+/]*[+/])(?=[A-Za-z0-9+/]*\d)(?=[A-Za-z0-9+/]*[a-z])(?=[A-Za-z0-9+/]*[A-Z])[A-Za-z0-9+/]{60,}={0,2}(?![\w/+.\-])}
  # The server's own accounts (ssh, sudo and logind name them in the journal), as /etc/passwd has them.
  LOGIN_UIDS = 1000...65_534
  # Where a share's files are: a share's folder (named here when it isn't one the NAS has now),
  # and below a share's stand-in, its folders and files.
  SHARE_PATH = %r{((?:/srv/pools/[^/\s]+/shares|/var/lib/amahi-kai/files|/shares)/)([^/\s'"<>,;:)\]]+)}
  BELOW_SHARE = %r{(<share-\d+>)/([^\s'"<>,;:)\]]+)}

  def initialize(names = self.class.names)
    @names = names # { kind => [names] }, the longest first so "vault-old" goes before "vault"
    @standins = Hash.new { |h, kind| h[kind] = {} }
  end

  # This NAS's names, by the stand-in each takes.
  def self.names
    {
      'server-name' => [SystemInfo.hostname],
      'user' => User.pluck(:login, :name).flatten + logins,
      'share' => Share.pluck(:name, :path).flat_map { |name, path| [name, (File.basename(path) if path.present?)] },
      'pool' => pool_names,
      'device' => Host.pluck(:name) + DnsAlias.pluck(:name) + PortForward.pluck(:name)
    }.transform_values { |list| list.compact.map(&:to_s).reject { |n| n.length < 3 }.uniq.sort_by { |n| -n.length } }
  end

  def self.logins
    names = []
    Etc.passwd { |entry| names << entry.name if LOGIN_UIDS.cover?(entry.uid) }
    names
  rescue StandardError
    []
  end

  def self.pool_names
    StoragePools.status[:pools].select(&:managed?).map(&:name)
  rescue StandardError
    []
  end

  def scrub(text)
    text = text.to_s.dup
    text = text.gsub(ARMOR) do |block|
      kind = Regexp.last_match(1)
      block.end_with?("-----END #{kind}-----") ? "-----BEGIN #{kind}----- <key-text> -----END #{kind}-----" : "-----BEGIN #{kind}----- <key-text>"
    end
    text = text.gsub(SSH_PUBLIC_KEY) { "#{Regexp.last_match(1)} <ssh-key>" }
    text = text.gsub(KEY_FINGERPRINT, 'SHA256:<key-fingerprint>')
    text = text.gsub(MD5_FINGERPRINT, 'MD5:<key-fingerprint>')
    text = text.gsub(BASE64_RUN, '<key-text>')
    text = text.gsub(SECRET) { |token| token.match?(HEX_HASH) || token.match?(UUID) ? token : '<secret>' }
    text = text.gsub(EMAIL) { |email| standin('email', email) }
    text = text.gsub(TAILNET) { |name| standin('tailnet-name', name.downcase) }
    text = text.gsub(MAC) { |mac| standin('mac', mac.downcase) }
    text = text.gsub(IPV4) { |address| ipv4(address) }
    text = text.gsub(IPV6) { |address| ipv6(address) }
    text = text.gsub(SHARE_PATH) { "#{Regexp.last_match(1)}#{share_folder(Regexp.last_match(2))}" }
    text = names(text)
    text.gsub(BELOW_SHARE) { "#{Regexp.last_match(1)}/#{below_share(Regexp.last_match(2))}" }
  end

  private

  def standin(kind, name)
    @standins[kind][name] ||= kind == 'server-name' ? '<server-name>' : "<#{kind}-#{@standins[kind].size + 1}>"
  end

  # Each name as a whole word (or path part), any case; the same name, whatever its case, one stand-in.
  def names(text)
    @names.each do |kind, list|
      list.each do |name|
        text = text.gsub(/(?<![\w-])#{Regexp.escape(name)}(?![\w-])/i) { standin(kind, name.downcase) }
      end
    end
    text
  end

  def ipv4(address)
    ip = IPAddr.new(address)
    return address if ip.loopback? || address == '0.0.0.0' || address.start_with?('255.')

    standin(ip.private? ? 'lan-address' : 'address', address)
  rescue IPAddr::InvalidAddressError
    address
  end

  def ipv6(address)
    return address unless address.count(':') >= 3 || address.include?('::')

    ip = IPAddr.new(address)
    return address if ip.loopback? || address == '::'

    standin('ipv6-address', ip.to_s)
  rescue IPAddr::InvalidAddressError
    address
  end

  # A share's folder by its stand-in: one the NAS has gets the same one as its name.
  def share_folder(name)
    standin('share', name.downcase)
  end

  # What's below a share: each folder and file by a stand-in of its own.
  def below_share(rest)
    rest.split('/', -1).map do |part|
      next part if part.empty? || part.start_with?('<')

      standin(File.extname(part).empty? ? 'folder' : 'file', part)
    end.join('/')
  end
end

require 'rails_helper'

# Every address of Amahi-kai or one of its apps is made in one place: DockerApp#url for an app,
# ApplicationHelper#amahi_url for Amahi-kai. HTTPS, when it comes, is an optional front door
# (docs/plans/roadmap.md) that changes those two, so nothing else may build an http:// address
# from a host or port. Links to other machines (DNS aliases) are theirs to make.
RSpec.describe 'Addresses of Amahi-kai and its apps' do
  it 'are made by DockerApp#url and amahi_url only' do
    allowed = %w[app/models/docker_app.rb app/helpers/application_helper.rb app/views/network/_dns_alias.html.slim]
    built = %r{https?://(?:#\{|<%=|\$\{|["'`] *\+)}
    offenders = Dir[Rails.root.join('{app,lib}/**/*.{rb,erb,slim,js}')].flat_map do |path|
      file = path.delete_prefix("#{Rails.root}/")
      next [] if allowed.include?(file)

      File.readlines(path).each_with_index.filter_map { |line, i| "#{file}:#{i + 1}" if line.match?(built) }
    end
    expect(offenders).to eq([])
  end

  it "makes Amahi-kai's own address on the web UI's port" do
    expect(ApplicationController.helpers.amahi_url('100.101.102.103')).to eq('http://100.101.102.103:3000/')
    expect(DockerApp.new(host_port: 8484).url('192.168.1.111')).to eq('http://192.168.1.111:8484/')
  end

  it "makes an app's address HTTPS when its manifest says its page is (web_tls)" do
    allow(AppCatalog).to receive(:find).and_call_original
    allow(AppCatalog).to receive(:find).with('bitshare').and_return({ web_tls: true })
    expect(DockerApp.new(identifier: 'bitshare', host_port: 8443).url('192.168.1.111')).to eq('https://192.168.1.111:8443/')
    expect(DockerApp.new(identifier: 'gitea', host_port: 3300).url('192.168.1.111')).to eq('http://192.168.1.111:3300/')
  end
end

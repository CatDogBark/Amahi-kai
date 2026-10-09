require 'rails_helper'

# The policy is enforced (not report-only): scripts only from Amahi-kai itself, no inline
# scripts; logos from https sites; the PDF preview's frame from Amahi-kai itself.
RSpec.describe 'Content-Security-Policy', type: :request do
  def directives(header)
    header.split(';').map(&:strip).to_h { |d| name, *values = d.split; [name, values] }
  end

  it 'is enforced on every page, with scripts from this site only' do
    login_as_admin
    ['/', '/shares', '/files', '/settings/system_status', '/apps', '/login'].each do |path|
      get path
      expect(response.headers['Content-Security-Policy-Report-Only']).to be_nil, path
      policy = directives(response.headers['Content-Security-Policy'].to_s)
      expect(policy['script-src']).to eq(["'self'"]), path
      expect(policy['default-src']).to eq(["'self'"]), path
      expect(policy['object-src']).to eq(["'none'"]), path
      expect(policy['frame-src']).to eq(["'self'"]), path
      expect(policy['img-src']).to include("'self'", 'https:'), path
      expect(policy['form-action']).to eq(["'self'"]), path
    end
  end

  it 'stays as it is for files from shares: a sandbox, and none for a PDF' do
    login_as_admin
    dir = Dir.mktmpdir
    File.write("#{dir}/page.html", '<script>alert(1)</script>')
    File.write("#{dir}/doc.pdf", "%PDF-1.4\n")
    share = create(:share, name: 'Docs', path: dir)
    get file_browser_raw_path(share, path: 'page.html')
    expect(response.headers['Content-Security-Policy']).to eq('sandbox')
    get file_browser_raw_path(share, path: 'doc.pdf')
    expect(response.headers['Content-Security-Policy']).to be_nil
    expect(response.headers['Content-Security-Policy-Report-Only']).to be_nil
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end

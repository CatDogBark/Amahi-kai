require 'spec_helper'
require 'site_apps'

# script/site-apps' logic: the website's app grid, written from an app catalog's manifests.
RSpec.describe SiteApps do
  let(:dir) { Dir.mktmpdir }
  let(:page) { "<div class=\"apps\">\n      <!-- apps -->\n      <p>old</p>\n      <!-- /apps -->\n    </div>\n" }

  after { FileUtils.rm_rf(dir) }

  def manifest(id, text)
    File.write("#{dir}/#{id}.yml", text)
  end

  def names(text)
    text[text.index(SiteApps::FIRST)..text.index(SiteApps::LAST)].scan(%r{<b>([^<]+)</b>}).flatten
  end

  it 'lists the apps by name, as the Apps page does, each with its logo, name and description' do
    manifest('zeta', "name: zeta\ndescription: Last.\nlogo: https://example.com/zeta.png\n")
    manifest('alpha', "name: Alpha\ndescription: First.\nlogo: https://example.com/alpha.svg\n")
    written = described_class.page(dir, page)
    expect(names(written)).to eq(%w[Alpha zeta])
    expect(written).to include('<img src="https://example.com/alpha.svg" alt=""', '<b>Alpha</b><span>First.</span>')
    expect(written).not_to include('old')
  end

  it "keeps the page around its markers, at the opening marker's indentation" do
    manifest('a', "name: A\n")
    written = described_class.page(dir, page)
    expect(written).to start_with("<div class=\"apps\">\n      <!-- apps -->\n      <div class=\"app glass\">")
    expect(written).to end_with("</div></div>\n      <!-- /apps -->\n    </div>\n")
    expect(described_class.page(dir, written)).to eq(written)
  end

  it 'escapes what the manifests say' do
    manifest('x', "name: \"<script>x</script>\"\ndescription: \"Tom & Jerry's <b>\"\n")
    written = described_class.page(dir, page)
    expect(written).to include('&lt;script&gt;x&lt;/script&gt;', 'Tom &amp; Jerry&#39;s &lt;b&gt;')
    expect(written).not_to include('<script>')
  end

  it 'draws a box for an app whose logo is missing or not a plain https link' do
    manifest('a', "name: A\nlogo: http://example.com/a.png\n")
    manifest('b', "name: B\nlogo: 'https://example.com/b.png\" onerror=\"x'\n")
    manifest('c', "name: C\n")
    written = described_class.page(dir, page)
    expect(written.scan('<span class="icon-tile">').size).to eq(3)
    expect(written).not_to include('<img', 'onerror')
  end

  it 'skips files that are not app manifests, and refuses a catalog with no apps' do
    manifest('list', "- not\n- an app\n")
    File.write("#{dir}/README.md", "name: not a manifest\n")
    expect { described_class.page(dir, page) }.to raise_error(ArgumentError, /no apps/)
  end

  it 'refuses a page without its markers' do
    manifest('a', "name: A\n")
    expect { described_class.page(dir, "<div>\n</div>\n") }.to raise_error(ArgumentError, /<!-- apps -->/)
  end

  it 'writes the website from the catalog that comes with Amahi-kai' do
    catalog = File.expand_path('../../config/apps', __dir__)
    expected = Dir["#{catalog}/*.yml"].map { |path| YAML.safe_load_file(path)['name'] }
    expect(names(described_class.page(catalog))).to match_array(expected)
  end
end

# frozen_string_literal: true

require 'cgi'
require 'yaml'

# The website's app grid (site/index.html, between its <!-- apps --> and <!-- /apps --> lines),
# written from an app catalog: each app's logo, name and description, in the Apps page's order
# (AppCatalog.all's, by name). script/site-apps runs it, and the site's deploy runs that on the
# catalog's repo, so amahi-kai.com lists what the catalog has without anyone editing the page.
module SiteApps
  PAGE = File.expand_path('../site/index.html', __dir__)
  FIRST = '<!-- apps -->'
  LAST = '<!-- /apps -->'
  # An app without a logo gets a box, drawn like the feature cards' icons.
  BOX = '<span class="icon-tile"><svg aria-hidden="true" focusable="false" xmlns="http://www.w3.org/2000/svg" ' \
        'width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' \
        'stroke-linecap="round" stroke-linejoin="round"><path d="M21 8 12 3 3 8v8l9 5 9-5z"/>' \
        '<path d="m3 8 9 5 9-5"/><path d="M12 13v8"/></svg></span>'

  module_function

  # The catalog's apps (each manifest with a name), by name as the Apps page lists them.
  def apps(dir)
    found = Dir[File.join(dir, '*.yml')].filter_map do |path|
      data = YAML.safe_load_file(path)
      data if data.is_a?(Hash) && data['name'].is_a?(String) && !data['name'].strip.empty?
    end
    raise ArgumentError, "no apps in #{dir}" if found.empty?

    found.sort_by { |app| app['name'].downcase }
  end

  # One app's tile. The logo is the manifest's own link (https only), as on the Apps page.
  def tile(app)
    logo = app['logo'].to_s
    picture = if logo.match?(%r{\Ahttps://[^\s"'<>]+\z})
                %(<span class="app-logo"><img src="#{CGI.escapeHTML(logo)}" alt="" width="28" height="28" ) +
                  %(loading="lazy" referrerpolicy="no-referrer"></span>)
              else
                BOX
              end
    %(<div class="app glass">#{picture}<div><b>#{CGI.escapeHTML(app['name'].strip)}</b>) +
      %(<span>#{CGI.escapeHTML(app['description'].to_s.strip)}</span></div></div>)
  end

  # +text+ (the page) with the lines between its markers written from +dir+'s apps, at the
  # opening marker's indentation.
  def page(dir, text = File.read(PAGE))
    first = text.index(FIRST) or raise ArgumentError, "the page has no #{FIRST} line"
    last = text.index(LAST, first) or raise ArgumentError, "the page has no #{LAST} line after #{FIRST}"
    indent = text[0...first][/[ \t]*\z/]
    lines = apps(dir).map { |app| "#{indent}#{tile(app)}\n" }
    "#{text[0, first + FIRST.length]}\n#{lines.join}#{indent}#{text[last..]}"
  end
end

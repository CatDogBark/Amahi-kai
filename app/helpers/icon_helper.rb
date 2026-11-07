module IconHelper
  # One of Amahi-kai's own icons (app/assets/images/icons, part of the code), named in the views:
  # a name that isn't one (lowercase letters, digits and hyphens) is no icon, so nothing outside
  # that folder is ever read.
  def lucide_icon(name, size: 18, css_class: '', **attrs)
    return '' unless name.to_s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)

    path = Rails.root.join('app', 'assets', 'images', 'icons', "#{name}.svg")
    return '' unless File.exist?(path)
    svg = File.read(path)
    svg = svg.sub('width="24"', "width=\"#{size}\"")
             .sub('height="24"', "height=\"#{size}\"")
    svg = svg.sub('<svg', "<svg class=\"lucide-icon #{ERB::Util.html_escape(css_class)}\"") unless css_class.empty?
    attrs.each { |k, v| svg = svg.sub('<svg', "<svg #{ERB::Util.html_escape(k)}=\"#{ERB::Util.html_escape(v)}\"") }
    # Safe: the SVG is our own file and every value added to it is escaped above.
    svg.html_safe # rubocop:disable Rails/OutputSafety
  end
end

module IconHelper
  def lucide_icon(name, size: 18, css_class: '', **attrs)
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

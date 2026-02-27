module IconHelper
  def lucide_icon(name, size: 18, css_class: '', **attrs)
    path = Rails.root.join('app', 'assets', 'images', 'icons', "#{name}.svg")
    return '' unless File.exist?(path)
    svg = File.read(path)
    svg = svg.sub('width="24"', "width=\"#{size}\"")
             .sub('height="24"', "height=\"#{size}\"")
    svg = svg.sub('<svg', "<svg class=\"lucide-icon #{css_class}\"") unless css_class.empty?
    attrs.each { |k, v| svg = svg.sub('<svg', "<svg #{k}=\"#{v}\"") }
    svg.html_safe
  end
end

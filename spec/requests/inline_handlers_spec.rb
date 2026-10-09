require 'rails_helper'

# Content-Security-Policy refuses inline event handlers, so the views have none: a button says
# what it does in its markup (data-call, lib/dispatch.js). Lines inside a page's own <script>
# are its JavaScript, which goes to the files next.
RSpec.describe 'the views' do
  it 'have no inline event handlers' do
    offenders = Dir[Rails.root.join('app/views/**/*.{erb,slim}')].flat_map do |file|
      inside = false
      File.readlines(file).each_with_index.filter_map do |line, i|
        inside = true if line.match?(/<script\b/)
        was_inside = inside
        inside = false if line.include?('</script>')
        next if was_inside
        "#{file.delete_prefix("#{Rails.root}/")}:#{i + 1}" if line.match?(/\bon(click|change|submit|input|key\w+|load|mouse\w+|error|focus|blur)\s*=/)
      end
    end
    expect(offenders).to eq([])
  end
end

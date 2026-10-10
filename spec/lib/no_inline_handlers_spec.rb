require 'rails_helper'

# The Content-Security-Policy refuses inline scripts, event handlers included: one in a
# template does nothing (#123), and the browser only says so when the event fires, so a page
# can load clean with a dead confirmation in it (Power off and Reboot went without asking).
# Templates say what a control does with data-call, data-confirm and the like (lib/dispatch.js,
# lib/application.js).
RSpec.describe 'templates' do
  HANDLER = /\bon(?:click|submit|change|input|load|error|key(?:up|down|press)|focus|blur|mouse\w+|dbl\w*)\b\s*(?:=|:|['"]\s*=>)/

  it 'have no inline event handlers' do
    offenders = Dir[Rails.root.join('app/{views,helpers}/**/*.{erb,slim,rb}')].flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, i|
        "#{file.delete_prefix("#{Rails.root}/")}:#{i + 1}: #{line.strip}" if line.match?(HANDLER)
      end
    end
    expect(offenders).to eq([])
  end

  it 'would find one, in any of the ways a template can write it' do
    ['<a onclick="go()">', 'button onclick="go()"', 'form: { onsubmit: "return confirm(1)" }', "'onchange' => 'x'"].each do |code|
      expect(code).to match(HANDLER), code
    end
    ['data-action="click->x#y"', 'online: true', 'data-confirm="Sure?"'].each { |code| expect(code).not_to match(HANDLER), code }
  end
end

require 'rails_helper'

# Content-Security-Policy refuses inline scripts and event handlers, so the views have none: a
# button says what it does in its markup (data-call, lib/dispatch.js), and each page's
# JavaScript is a file of its own. (A <script type="application/json"> is data, not a script.)
RSpec.describe 'the views' do
  def offenders(pattern)
    Dir[Rails.root.join('app/views/**/*.{erb,slim}')].flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, i|
        "#{file.delete_prefix("#{Rails.root}/")}:#{i + 1}" if line.match?(pattern)
      end
    end
  end

  it 'have no inline event handlers' do
    expect(offenders(/\bon(click|change|submit|input|key\w+|load|mouse\w+|error|focus|blur)\s*=/)).to eq([])
  end

  it 'have no inline scripts' do
    expect(offenders(/<script(?![^>]*type="application\/json")|^\s*javascript:\s*$/)).to eq([])
  end
end

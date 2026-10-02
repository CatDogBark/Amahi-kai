require "spec_helper"

# The website (site/) is built separately by GitHub Pages and keeps its own copy of the
# ocean background. Run script/sync-ocean-assets after editing the originals.
RSpec.describe "Ocean background assets" do
  root = File.expand_path("../..", __dir__)

  {
    "app/assets/javascripts/ocean.js" => "site/assets/ocean.js",
    "app/assets/stylesheets/ocean-bg.css" => "site/assets/ocean.css",
  }.each do |source, copy|
    it "keeps #{copy} identical to #{source}" do
      expect(File.read(File.join(root, copy))).to eq(File.read(File.join(root, source))),
        "#{copy} is out of date: run script/sync-ocean-assets"
    end
  end
end

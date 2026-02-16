require 'spec_helper'

RSpec.describe Webapp, type: :model do
  # Webapp hooks (before_validation, after_save) try to write conf files
  # and create directories, so we test only pure methods here.

  describe "#php5?" do
    it "returns true for PHP5 kind" do
      webapp = Webapp.new(kind: "PHP5")
      expect(webapp).to be_php5
    end

    it "returns false for other kinds" do
      webapp = Webapp.new(kind: "generic")
      expect(webapp).not_to be_php5
    end

    it "returns false when kind is nil" do
      webapp = Webapp.new(kind: nil)
      expect(webapp).not_to be_php5
    end
  end

  describe "#full_url" do
    it "returns http URL with name and domain" do
      webapp = Webapp.new(name: "myapp")
      domain = Setting.value_by_name('domain')
      expect(webapp.full_url).to eq("http://myapp.#{domain}")
    end
  end

  describe "created via SQL (bypassing hooks)" do
    def create_webapp(attrs = {})
      defaults = {
        name: "testapp",
        fname: "1001-testapp.conf",
        path: "/tmp/test-webapp",
        deletable: false,
        created_at: Time.current,
        updated_at: Time.current
      }
      merged = defaults.merge(attrs)
      cols = merged.keys.map(&:to_s)
      vals = merged.values.map { |v| v.nil? ? "NULL" : ActiveRecord::Base.connection.quote(v) }
      ActiveRecord::Base.connection.execute(
        "INSERT INTO webapps (#{cols.join(',')}) VALUES (#{vals.join(',')})"
      )
      Webapp.find_by(name: merged[:name])
    end

    it "has correct attributes" do
      webapp = create_webapp(name: "mysite", path: "/var/hda/web-apps/mysite")
      expect(webapp.name).to eq("mysite")
      expect(webapp.path).to eq("/var/hda/web-apps/mysite")
    end

    it "returns full_url correctly" do
      webapp = create_webapp(name: "wiki")
      domain = Setting.value_by_name('domain')
      expect(webapp.full_url).to eq("http://wiki.#{domain}")
    end
  end
end

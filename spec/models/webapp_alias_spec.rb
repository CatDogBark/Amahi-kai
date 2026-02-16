require 'spec_helper'

describe WebappAlias do

  before(:each) do
    create(:admin)
    create(:setting, name: "net", value: "1")
    create(:setting, name: "self-address", value: "1")
    # Insert a webapp via raw SQL to avoid Webapp's initialize hooks
    ActiveRecord::Base.connection.execute(
      "INSERT INTO webapps (name, path, kind, fname, deletable, login_required) VALUES ('testapp', '/var/hda/web-apps/testapp', 'web', 'testapp', 1, 0)"
    )
    @webapp = Webapp.last
    # Stub save hooks on the webapp to avoid system calls
    def @webapp.after_save_hook; end
    def @webapp.after_destroy_hook; end
    def @webapp.before_create_hook; end
  end

  def build_alias(attrs = {})
    defaults = { name: "myalias", webapp: @webapp }
    WebappAlias.new(defaults.merge(attrs))
  end

  it "should belong to a webapp" do
    wa = WebappAlias.create!(name: "myalias", webapp: @webapp)
    expect(wa.webapp).to eq(@webapp)
  end

  it "should require a name" do
    expect(build_alias(name: nil)).not_to be_valid
    expect(build_alias(name: "")).not_to be_valid
  end

  it "should require a unique name" do
    WebappAlias.create!(name: "uniquealias", webapp: @webapp)
    expect(build_alias(name: "uniquealias")).not_to be_valid
  end

  it "should require name length between 1 and 254" do
    expect(build_alias(name: "a" * 255)).not_to be_valid
    expect(build_alias(name: "a")).to be_valid
    expect(build_alias(name: "a" * 254)).to be_valid
  end

  it "should require name to match the format regex" do
    expect(build_alias(name: "valid")).to be_valid
    expect(build_alias(name: "sub.domain")).to be_valid
    expect(build_alias(name: "a1-b2.c3")).to be_valid
    expect(build_alias(name: "-invalid")).not_to be_valid
    expect(build_alias(name: ".invalid")).not_to be_valid
    expect(build_alias(name: "inva lid")).not_to be_valid
  end

  it "should return name from to_s" do
    wa = build_alias(name: "myalias")
    expect(wa.to_s).to eq("myalias")
  end

  it "should call save on webapp after save" do
    saved = false
    original_save = @webapp.method(:save)
    @webapp.define_singleton_method(:save) do |*args|
      saved = true
      original_save.call(*args)
    end
    WebappAlias.create!(name: "triggersave", webapp: @webapp)
    expect(saved).to be true
  end

  it "should call save on webapp after destroy" do
    wa = WebappAlias.create!(name: "destroyme", webapp: @webapp)
    saved = false
    @webapp.define_singleton_method(:save) do |*args|
      saved = true
      true
    end
    wa.destroy
    expect(saved).to be true
  end
end

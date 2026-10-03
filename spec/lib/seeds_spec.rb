require 'rails_helper'

# bin/amahi-install runs db:seed on every install, including a re-run on a live system.
RSpec.describe "db/seeds.rb" do
  def run_seeds
    load Rails.root.join("db/seeds.rb").to_s
  end

  it "leaves an existing system alone" do
    user = create(:user)
    create(:share)
    Setting.set('advanced', '0')

    expect { run_seeds }.not_to change { [User.count, Share.count] }
    expect(User.exists?(user.id)).to be true
    expect(Setting.get('advanced')).to eq('0')
  end

  it "creates the admin account on an empty database" do
    User.delete_all
    run_seeds
    expect(User.find_by(login: 'admin')).to be_present
  end
end

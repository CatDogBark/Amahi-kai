require 'rails_helper'

# db/seeds.rb on an empty database, as bin/amahi-install runs it. (spec_helper seeds before every
# example with the public development password; these start from no users.)
RSpec.describe 'db/seeds.rb' do
  let(:seeds) { Rails.root.join('db/seeds.rb').to_s }
  let(:admin) { User.find_by(login: User::SEED_ADMIN_LOGIN) }

  before { User.delete_all }

  after { ENV.delete('AMAHI_FIRST_PASSWORD_FILE') }

  def password_file(text)
    file = Tempfile.new('first-password')
    file.write(text)
    file.close
    ENV['AMAHI_FIRST_PASSWORD_FILE'] = file.path
    file.path
  end

  it "gives the admin the installer's random password, deletes its file, and keeps only its hash" do
    path = password_file("Xk3f9QvL2mT8wRz5BnYc\n")
    load seeds
    expect(admin.authenticate('Xk3f9QvL2mT8wRz5BnYc')).to be_truthy
    expect(admin.authenticate(User::SEED_ADMIN_PASSWORD)).to be false
    expect(File.exist?(path)).to be false
    expect(Setting.get(User::FIRST_PASSWORD_SETTING)).to eq(admin.password_digest)
    expect(Setting.get(User::FIRST_PASSWORD_SETTING)).not_to include('Xk3f9QvL2mT8wRz5BnYc')
  end

  it 'refuses a first password shorter than 12 characters' do
    password_file('short')
    expect { load seeds }.to raise_error(/shorter than 12/)
    expect(admin).to be_nil
  end

  it "won't seed the public password in production" do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect { load seeds }.to raise_error(/AMAHI_FIRST_PASSWORD_FILE/)
    expect(admin).to be_nil
  end

  it 'leaves an existing install alone, file and all' do
    create(:admin)
    path = password_file('Xk3f9QvL2mT8wRz5BnYc')
    load seeds
    expect(File.exist?(path)).to be true
    expect(User.find_by(login: User::SEED_ADMIN_LOGIN)).to be_nil
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end

require 'rails_helper'

# System Update: the page starts the job (the root helper's system.update) and follows
# /var/log/amahi-kai/update.log, reconnecting with ?from= while the app restarts.
RSpec.describe 'System Update', type: :request do
  let(:log) { Tempfile.new('update.log') }

  before do
    login_as_admin
    allow(Rails.env).to receive(:production?).and_return(true)
    stub_const('SettingsController::UPDATE_LOG', log.path)
    allow_any_instance_of(SettingsController).to receive(:sleep)
  end

  after { log.close! }

  def job_states(*states)
    results = states.map { |state| ["#{state}\n", '', instance_double(Process::Status, success?: state == 'active')] }
    allow(Open3).to receive(:capture3).with('systemctl', 'is-active', 'amahi-kai-update.service').and_return(*results)
  end

  def events(body)
    body.split("\n\n").map { |chunk| chunk.lines.map(&:chomp) }.reject { |lines| lines.all?(&:empty?) }
  end

  it "shows the deployed commit on System Status" do
    allow(SystemServices).to receive(:app_commit).and_return('abc1234')
    get '/settings/system_status'
    expect(response.body).to include('abc1234')
  end

  describe 'starting it' do
    it 'starts the job through the root helper' do
      post '/settings/update_system', as: :json
      expect(response.parsed_body).to eq('status' => 'ok')
      expect(Privileged.calls).to eq([['system.update', {}]])
    end

    it "says why when the job couldn't start" do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('system.update', "System Update's job isn't installed yet"))
      post '/settings/update_system', as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include("isn't installed yet")
    end
  end

  describe 'following its log' do
    it 'streams the log as it grows and ends when the job does' do
      File.write(log.path, "Setting file ownership...\nPulling latest code...\n")
      job_states('active', 'inactive')
      allow(File).to receive(:readlines).and_call_original
      reads = 0
      allow(File).to receive(:readlines).with(log.path, chomp: true) do
        reads += 1
        File.open(log.path, 'a') { |f| f.puts('✓ Amahi-kai updated and running!') } if reads == 1
        File.read(log.path).lines.map(&:chomp).then { |lines| reads == 1 ? lines.first(2) : lines }
      end

      get '/settings/update_system_stream', headers: same_origin

      expect(events(response.body)).to eq([
                                            ['data: Setting file ownership...'], ['data: Pulling latest code...'],
                                            ['data: ✓ Amahi-kai updated and running!'], ['event: done', 'data: success']
                                          ])
    end

    it 'picks up after the lines the page already has, and reports a failed update' do
      File.write(log.path, "Pulling latest code...\nRunning database migrations...\n✗ Update failed at: Running database migrations.\n")
      job_states('inactive')

      get '/settings/update_system_stream', params: { from: 1 }, headers: same_origin

      expect(events(response.body)).to eq([
                                            ['data: Running database migrations...'],
                                            ['data: ✗ Update failed at: Running database migrations.'],
                                            ['event: done', 'data: error']
                                          ])
    end
  end
end

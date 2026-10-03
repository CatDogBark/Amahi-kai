require 'spec_helper'

RSpec.describe UserSession, type: :model do
  let(:user) { create(:admin) }

  # Mock controller for UserSession
  let(:mock_controller) do
    controller = double('controller')
    session_hash = {}
    allow(controller).to receive(:session).and_return(session_hash)
    allow(controller).to receive(:reset_session)
    allow(controller).to receive(:request).and_return(
      double('request', remote_ip: '127.0.0.1')
    )
    controller
  end

  before do
    UserSession.controller = mock_controller
  end

  # What a real login leaves in the session (UserSession#save).
  def signed_in_as(user)
    mock_controller.session[:user_id] = user.id
    mock_controller.session[:session_token] = user.session_token
  end

  describe '#initialize' do
    it 'accepts login and password' do
      session = UserSession.new(login: 'testuser', password: 'secret')
      expect(session.login).to eq('testuser')
      expect(session.password).to eq('secret')
    end

    it 'is not persisted' do
      session = UserSession.new
      expect(session.persisted?).to be false
    end
  end

  describe '#save' do
    it 'authenticates with valid credentials' do
      session = UserSession.new(login: user.login, password: 'secretpassword')
      expect(session.save).to be true
      expect(session.record).to eq(user)
    end

    it 'stores user_id in session' do
      session = UserSession.new(login: user.login, password: 'secretpassword')
      session.save
      expect(mock_controller.session[:user_id]).to eq(user.id)
    end

    it 'rejects invalid password' do
      session = UserSession.new(login: user.login, password: 'wrongpassword')
      expect(session.save).to be false
      expect(session.record).to be_nil
    end

    it 'rejects nonexistent user' do
      session = UserSession.new(login: 'nobody', password: 'secretpassword')
      expect(session.save).to be false
    end

    it 'is case-insensitive for login' do
      session = UserSession.new(login: user.login.upcase, password: 'secretpassword')
      expect(session.save).to be true
    end

    it 'adds error on failure' do
      session = UserSession.new(login: user.login, password: 'wrong')
      session.save
      expect(session.errors[:base]).to include('Invalid username or password')
    end

    it 'updates login tracking columns' do
      session = UserSession.new(login: user.login, password: 'secretpassword')
      session.save
      user.reload
      expect(user.current_login_at).not_to be_nil
      expect(user.current_login_ip).to eq('127.0.0.1')
      expect(user.login_count).to be >= 1
    end
  end

  describe '.find' do
    it 'returns nil when no session' do
      expect(UserSession.find).to be_nil
    end

    it 'returns session when user_id is in session' do
      signed_in_as(user)
      found = UserSession.find
      expect(found).not_to be_nil
      expect(found.record).to eq(user)
    end

    it 'returns nil for invalid user_id' do
      mock_controller.session[:user_id] = 99999
      expect(UserSession.find).to be_nil
    end
  end

  describe '#destroy' do
    it 'clears the session' do
      signed_in_as(user)
      session = UserSession.find
      session.destroy
      expect(mock_controller.session[:user_id]).to be_nil
    end

    it 'calls reset_session' do
      signed_in_as(user)
      session = UserSession.find
      expect(mock_controller).to receive(:reset_session)
      session.destroy
    end
  end

  describe '.controller' do
    it 'keeps each thread\'s controller separate' do
      controller_a = double('controller A')
      controller_b = double('controller B')
      ready = Queue.new
      go = Queue.new
      seen = {}

      threads = { a: controller_a, b: controller_b }.map do |key, controller|
        Thread.new do
          UserSession.controller = controller
          ready << true
          go.pop
          seen[key] = UserSession.controller
        end
      end
      2.times { ready.pop }  # both threads have set their controller
      2.times { go << true }
      threads.each(&:join)

      expect(seen).to eq(a: controller_a, b: controller_b)
    end
  end

  describe '#save session reset' do
    it 'resets the session before storing the user' do
      session = UserSession.new(login: user.login, password: 'secretpassword')
      session.save
      expect(mock_controller).to have_received(:reset_session)
    end
  end
  describe 'session token and idle timeout' do
    let(:store) { mock_controller.session }

    def log_in
      UserSession.new(login: user.login, password: 'secretpassword').save
    end

    it 'stores the user\'s session token and the time at login' do
      log_in
      expect(store[:session_token]).to eq(user.reload.session_token)
      expect(store[:seen_at]).to be_within(5).of(Time.current.to_i)
    end

    it 'ends a session whose token no longer matches (the password changed)' do
      log_in
      user.update!(password: 'changedpass1', password_confirmation: 'changedpass1')
      expect(UserSession.find).to be_nil
      expect(mock_controller).to have_received(:reset_session).twice  # login, then expiry
    end

    it 'ends a session unused for more than 7 days' do
      log_in
      store[:seen_at] = (8.days.ago).to_i
      expect(UserSession.find).to be_nil
    end

    it 'keeps an active session and refreshes its last-seen time' do
      log_in
      store[:seen_at] = (10.minutes.ago).to_i
      expect(UserSession.find&.record).to eq(user)
      expect(store[:seen_at]).to be_within(5).of(Time.current.to_i)
    end

    it 'keeps a session from before tokens existed for a user who has none' do
      user.update_column(:session_token, nil)
      store[:user_id] = user.id
      expect(UserSession.find&.record).to eq(user)
    end
  end
end

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
      mock_controller.session[:user_id] = user.id
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
      mock_controller.session[:user_id] = user.id
      session = UserSession.find
      session.destroy
      expect(mock_controller.session[:user_id]).to be_nil
    end

    it 'calls reset_session' do
      mock_controller.session[:user_id] = user.id
      session = UserSession.find
      expect(mock_controller).to receive(:reset_session)
      session.destroy
    end
  end
end

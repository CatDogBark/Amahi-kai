require 'rails_helper'

RSpec.describe UsersHelper, type: :helper do
  describe '#user_icon_class' do
    it 'returns user_admin for admin users' do
      user = double('user', admin: true, needs_auth?: false)
      expect(helper.user_icon_class(user)).to eq('user_admin')
    end

    it 'returns user_warn for users needing auth' do
      user = double('user', admin: false, needs_auth?: true)
      expect(helper.user_icon_class(user)).to eq('user_warn')
    end

    it 'returns empty string for regular users' do
      user = double('user', admin: false, needs_auth?: false)
      expect(helper.user_icon_class(user)).to eq('')
    end

    # needs_auth? takes precedence over admin
    it 'returns user_warn when admin also needs auth' do
      user = double('user', admin: true, needs_auth?: true)
      expect(helper.user_icon_class(user)).to eq('user_warn')
    end
  end

  describe '#confirm_user_destroy_message' do
    it 'includes the username' do
      msg = helper.confirm_user_destroy_message('testuser')
      expect(msg).to include('testuser')
    end

    it 'returns html_safe string' do
      msg = helper.confirm_user_destroy_message('testuser')
      expect(msg).to be_html_safe
    end
  end

  describe '#user_formatted_date' do
    it 'formats a valid date' do
      date = Time.current
      result = helper.user_formatted_date(date)
      expect(result).not_to eq('-')
      expect(result).to be_a(String)
    end

    it 'returns dash for nil date' do
      expect(helper.user_formatted_date(nil)).to eq('-')
    end
  end
end

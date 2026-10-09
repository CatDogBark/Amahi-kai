require 'rails_helper'

# Users in a real browser: creating a user from the form, and the password form's reveal and
# cancel (data-reveal, data-reveal-hide).
RSpec.describe 'Users', type: :system do
  it 'creates a user, shows the password form and hides it again, cleared' do
    sign_in_as_admin
    visit '/users'
    click_button 'New User'
    fill_in 'user[login]', with: 'ann'
    fill_in 'user[name]', with: 'Ann Example'
    fill_in 'user[password]', with: 'a-long-passphrase'
    fill_in 'user[password_confirmation]', with: 'a-long-passphrase'
    click_button 'Create'
    expect(page).to have_css('#users-table', text: 'ann')
    ann = User.find_by(login: 'ann')
    expect(ann).to be_present

    find("#whole_user_#{ann.id} td.users-col2", text: 'Ann Example').click # opens the row
    find("#user-password-control-action-#{ann.id}").click
    within("#edit_user_password_#{ann.id}") do
      expect(page).to have_css('.password-edit', visible: :visible)
      fill_in "password_#{ann.id}", with: 'something'
      click_link 'Cancel'
      expect(page).to have_css('.password-edit', visible: :hidden)
    end
    expect(find("#password_#{ann.id}", visible: :hidden).value).to eq('')
  end

  # A page that answers a form (a refused New User) asks for itself again when it's reloaded,
  # instead of sending the form a second time (form_reply.js).
  it "reloads a refused form's page without sending the form again" do
    requests = []
    subscriber = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*, payload|
      requests << [payload[:method], payload[:action]] if payload[:controller] == 'UsersController'
    end
    sign_in_as_admin
    visit '/users'
    click_button 'New User'
    page.execute_script("document.querySelectorAll('#new-user-form [required]').forEach(function(i) { i.removeAttribute('required'); })")
    fill_in 'user[login]', with: 'meow'
    fill_in 'user[password]', with: 'longenough1'
    fill_in 'user[password_confirmation]', with: 'longenough1'
    click_button 'Create'
    expect(page).to have_css('#new-user-form .alert-danger', text: "Name can't be blank")
    expect(page).to have_css('body[data-form-reply]')

    requests.clear
    page.execute_script('window.location.reload()')
    expect(page).to have_no_css('body[data-form-reply]')
    expect(page).to have_css('#users-table')
    expect(requests).to eq([%w[GET index]])
    # The refused form's answer is a 422, which Chrome logs as a failed load: expected here
    @browser_log.reject! { |entry| entry[:text].to_s.include?('status of 422') }
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  # The card is laid out like a share's: sections, each setting with what it does, Delete at the end.
  it "shows a user's card by section, and a role change swaps Delete for the admin note" do
    ann = User.create!(login: 'ann', name: 'Ann Example', password: 'a-long-passphrase', password_confirmation: 'a-long-passphrase', role: 'user')
    sign_in_as_admin
    visit '/users'
    find("#whole_user_#{ann.id} td.users-col2", text: 'Ann Example').click
    within("#about_user_#{ann.id}") do
      expect(page.all('h6.share-section-title').map { |title| title.text.downcase }).to eq(%w[account password])
      expect(page.all('.share-row-label').map(&:text)).to eq(['Full name', 'Role', 'Last sign-in', 'Password'])
      expect(page).to have_css("#user-last-login-#{ann.id}", text: 'Never')
      expect(page).to have_button('Change password')
      expect(page).to have_no_css('form.edit_name_form', visible: :visible) # until the name is clicked
      expect(page).to have_link('Delete ann', visible: :visible)

      find("#user-role-#{ann.id}").select('Admin')
      expect(page).to have_no_link('Delete ann', visible: :visible)
      expect(page).to have_css('[data-user-target="adminNote"]', text: "An admin can't be deleted", visible: :visible)
    end
    expect(ann.reload.role).to eq('admin')

    admin = User.find_by(login: User::SEED_ADMIN_LOGIN)
    find("#whole_user_#{admin.id} td.users-col1").click
    within("#about_user_#{admin.id}") do
      expect(page).to have_no_css("#user-role-#{admin.id}")
      expect(page).to have_text("You can't change your own role.")
    end
  end
end

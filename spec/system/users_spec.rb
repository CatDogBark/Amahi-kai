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
end

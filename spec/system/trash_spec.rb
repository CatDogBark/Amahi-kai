require 'rails_helper'

# The Trash in a real browser: the Keep files select saves on change (data-autosubmit).
RSpec.describe 'Trash', type: :system do
  it 'saves how long files are kept as soon as the select changes' do
    sign_in_as_admin
    visit '/files/trash'
    expect(page).to have_css('#trash-about', text: '30 days')
    select 'for 7 days', from: 'trash-days'
    expect(page).to have_css('#toast-container .amahi-toast', text: 'keeps files for 7 days')
    expect(Privileged.calls).to include(['trash.set_days', { days: 7 }])
  end
end

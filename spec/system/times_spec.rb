require 'rails_helper'

# Dates and times of day are written in the browser's time zone (time_ago.js, from the
# helper's local_time_tag): the server's clock runs in UTC, and its own reading put the
# dashboard's date and every time of day hours off for a viewer in Hawaii.
RSpec.describe "Times in the viewer's time zone", type: :system do
  # Chrome puts a narrow no-break space before AM and PM.
  def shown(element) = element.text(:all).gsub(/[  ]/, ' ').strip

  before do
    browser.command('Emulation.setTimezoneOverride', timezoneId: 'Pacific/Honolulu')
    browser.command('Emulation.setLocaleOverride', locale: 'en-US')
    sign_in_as_admin
  end

  it "writes the dashboard's date and a user's made time in the browser's zone, not the server's UTC" do
    hawaii = Time.current.in_time_zone('Pacific/Honolulu')
    visit '/'
    expect(shown(find('time[data-local="weekday-date"]'))).to eq(hawaii.strftime('%A, %B %-d, %Y'))

    admin = User.find_by(login: User::SEED_ADMIN_LOGIN)
    made = admin.created_at.in_time_zone('Pacific/Honolulu')
    visit '/users'
    created = find("#about_user_#{admin.id} time[data-local='short']", visible: :all)
    expect(shown(created)).to eq(made.strftime('%b %-d, %-l:%M %p'))
    expect(created['datetime']).to eq(admin.created_at.utc.iso8601)
  end
end

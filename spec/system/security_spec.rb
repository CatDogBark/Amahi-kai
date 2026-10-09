require 'rails_helper'

# The security audit in a real browser (security.js): from Network → Security and from Remote
# Access, its window streams the (simulated) audit to its summary.
RSpec.describe 'Security', type: :system do
  it 'runs the audit from the Security page' do
    sign_in_as_admin
    visit '/network/security'
    find('button', text: /audit/i).click
    within('#security-audit-install-modal') do
      expect(page).to have_css('#security-audit-output', text: 'Checking')
      expect(page).to have_css('#security-audit-output', text: 'Audit Complete', wait: 15)
      expect(page).to have_button('Close & Refresh')
    end
  end

  it 'loads Remote Access and runs the audit from there' do
    sign_in_as_admin
    visit '/network/remote_access'
    expect(page).to have_css('#tunnel-token-field')
    click_link 'Run security audit'
    within('#security-audit-install-modal') do
      expect(page).to have_css('#security-audit-output', text: 'Audit Complete', wait: 15)
    end
  end
end

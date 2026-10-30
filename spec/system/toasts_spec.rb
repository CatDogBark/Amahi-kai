require 'rails_helper'

# The flags (toast.js): an error stays until it's dismissed, so a refusal's reason can be read,
# and one where something broke also offers Report a problem; the others go by themselves after
# a few seconds.
RSpec.describe 'Toasts', type: :system do
  def flag(text)
    find('.amahi-toast', text: text)
  end

  # Clicked in the page, not at the button's place on screen: the flag slides in from the side,
  # and a click aimed while it moves can land beside the button.
  def press(element)
    page.execute_script('arguments[0].click()', element)
  end

  it 'keeps an error until it is dismissed, and lets a notice go by itself' do
    sign_in_as_admin
    page.execute_script("showToast('It was refused', 'error'); showToast('It was done', 'notice')")
    expect(page).to have_css('.amahi-toast', text: 'It was refused')
    timers = page.evaluate_script(<<~JS)
      Array.prototype.slice.call(document.querySelectorAll('.amahi-toast'))
        .filter(function(t) { return t.textContent.indexOf('It was') !== -1; })
        .map(function(t) { return t._timer !== undefined; })
    JS
    expect(timers).to eq([false, true]) # no timer to dismiss the error; the notice has one
    expect(flag('It was refused')).to have_no_link('Report this problem') # a refusal isn't a fault
    press(flag('It was refused').find('button', text: 'Dismiss'))
    expect(page).to have_no_css('.amahi-toast', text: 'It was refused')
  end

  it 'offers to report what broke, started with the flag and the page it came up on' do
    sign_in_as_admin
    visit '/files/trash'
    page.execute_script("showToast('Greyhole didn\\'t start: exit 2', 'failed')")
    link = flag("Greyhole didn't start").find_link('Report this problem')
    expect(URI(link[:href]).request_uri).to eq('/settings/help/report?about=Greyhole%20didn%27t%20start%3A%20exit%202&page=%2Ffiles%2Ftrash')
    press(flag("Greyhole didn't start").find('button', text: 'Dismiss'))
    expect(page).to have_no_css('.amahi-toast', text: "Greyhole didn't start")
  end

  # The Apps page reloads after Start or Stop; a flag shown before it would go with the old page
  it 'shows a flag left for the page a reload brings' do
    sign_in_as_admin
    page.execute_script("showToastAfterReload('That didn\\'t work: no answer', 'failed')")
    expect(page).to have_no_css('.amahi-toast', text: 'no answer')
    visit page.current_path
    expect(flag('no answer')).to have_link('Report this problem')
  end

  # A job in its window (an install, System Update) that ends in ✗ leaves a flag for the page its
  # button reloads
  it 'leaves a flag offering a report when a job in its window fails' do
    allow(DockerService).to receive_messages(installed?: true, running?: true)
    allow(Privileged).to receive(:call).and_wrap_original do |call, operation, **args|
      raise Privileged::Error.new(operation, 'docker exited 125: invalid mount config') if operation == 'apps.install'

      call.call(operation, **args)
    end
    sign_in_as_admin
    visit '/apps'
    within('#docker_app_uptimekuma') { click_button 'Install' }
    within('#app-install-modal') do
      expect(page).to have_text('✗ docker exited 125: invalid mount config', wait: 15)
      click_button 'Close & Refresh'
    end
    expect(flag('docker exited 125: invalid mount config')).to have_link('Report this problem')
  end
end

require 'rails_helper'

# The toasts (toast.js): an error stays until it's closed, so a refusal's reason can be read; the
# others go by themselves after a few seconds.
RSpec.describe 'Toasts', type: :system do
  it 'keeps an error until it is closed, and lets a notice go by itself' do
    sign_in_as_admin
    page.execute_script("showToast('It was refused', 'error'); showToast('It was done', 'notice')")
    expect(page).to have_css('.amahi-toast', text: 'It was refused')
    timers = page.evaluate_script(<<~JS)
      Array.prototype.slice.call(document.querySelectorAll('.amahi-toast'))
        .filter(function(t) { return t.textContent.indexOf('It was') !== -1; })
        .map(function(t) { return t._timer !== undefined; })
    JS
    expect(timers).to eq([false, true]) # no timer to dismiss the error; the notice has one
    # Clicked in the page, not at the button's place on screen: the toast slides in from the
    # side, and a click aimed while it moves can land beside the button.
    page.execute_script('arguments[0].click()', find('.amahi-toast', text: 'It was refused').find('.amahi-toast-close'))
    expect(page).to have_no_css('.amahi-toast', text: 'It was refused')
  end
end

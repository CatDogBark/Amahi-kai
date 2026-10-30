require 'rails_helper'

# Forms sent the ordinary way show they're working until the next page comes (lib/busy_forms.js):
# the buttons disabled, the pressed one with a spinner and "Working…" (or its data-disable-with),
# a "still working" flag after a while, and the form as it was when Back brings its page from the
# browser's cache. To look at a form while it works, the browser answers it with No Content: the
# page stays (as for a form that downloads a file), still working. A browser held on its way to the
# next page can't be looked at.
RSpec.describe 'Forms at work', type: :system do
  # A form like the pages' own, posting to the Trash's setting (with the CSRF token where the page
  # has one: tests turn the check off).
  def add_form(label: 'Save', disable_with: nil)
    page.execute_script(<<~JS, label, disable_with)
      var label = arguments[0], disableWith = arguments[1];
      var form = document.createElement('form');
      form.method = 'post';
      form.action = '/files/trash/keep';
      form.id = 'busy-test';
      var token = document.querySelector('meta[name=csrf-token]');
      var fields = [['days', '14']];
      if (token) fields.push(['authenticity_token', token.content]);
      fields.forEach(function(pair) {
        var input = document.createElement('input');
        input.type = 'hidden';
        input.name = pair[0];
        input.value = pair[1];
        form.appendChild(input);
      });
      var other = document.createElement('button');
      other.type = 'button';
      other.textContent = 'Other';
      form.appendChild(other);
      var button = document.createElement('button');
      button.type = 'submit';
      button.textContent = label;
      if (disableWith) button.dataset.disableWith = disableWith;
      form.appendChild(button);
      document.body.appendChild(form);
    JS
  end

  # The browser answers the form itself, with No Content, so the page stays where it is.
  def answer_with_no_content
    answered = []
    browser.network.intercept(pattern: '*/files/trash/keep*')
    browser.on(:request) do |request|
      answered << request.url
      request.respond(responseCode: 204, body: '')
    end
    answered
  end

  def send_form
    page.execute_script("document.querySelector('#busy-test button[type=submit]').click()")
  end

  before do
    sign_in_as_admin
    visit '/files/trash'
  end

  it "disables a form's buttons and says it's working until the next page comes" do
    page.execute_script('window.BUSY_FLAG_AFTER_MS = 300')
    add_form
    answered = answer_with_no_content
    send_form
    button = find('#busy-test button[type=submit]')
    expect(button).to have_text('Working…')
    expect(button).to have_css('.spinner-border')
    expect(button).to be_disabled
    expect(find('#busy-test button', text: 'Other')).to be_disabled # not sent twice from another button
    expect(page).to have_css('#busy-test[aria-busy="true"]')
    expect(page).to have_css('.amahi-toast', text: 'Still working on it')
    expect(answered.sole).to end_with('/files/trash/keep') # sent, with its button's state changed after
  end

  it 'puts a form back as it was when Back brings its page from the cache' do
    page.execute_script('window.BUSY_FLAG_AFTER_MS = 100')
    add_form(label: 'Keep', disable_with: 'Saving…')
    answer_with_no_content
    send_form
    button = find('#busy-test button[type=submit]')
    expect(button).to have_text('Saving…')
    expect(page).to have_css('.amahi-toast', text: 'Still working on it')
    page.execute_script("window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }))")
    expect(button).to have_text('Keep')
    expect(button).not_to be_disabled
    expect(find('#busy-test button', text: 'Other')).not_to be_disabled
    expect(page).to have_no_css('#busy-test[aria-busy]')
    expect(page).to have_no_css('.amahi-toast', text: 'Still working on it')
  end

  it 'still sends a form, its next page coming as before' do
    add_form
    send_form
    expect(page).to have_css('.amahi-toast', text: 'The Trash keeps files for 14 days.')
    expect(page).to have_no_css('#busy-test')
    expect(Privileged.calls).to include(['trash.set_days', { days: 14 }])
  end

  it 'leaves a form its own script sends to that script' do
    add_form
    page.execute_script(<<~JS)
      document.getElementById('busy-test').addEventListener('submit', function(event) {
        event.preventDefault();
        event.target.dataset.sent = 'by its script';
      });
    JS
    send_form
    expect(page).to have_css('#busy-test[data-sent="by its script"]')
    page.evaluate_async_script('setTimeout(arguments[0], 100)') # past the handler's own turn
    button = find('#busy-test button[type=submit]')
    expect(button).to have_text('Save')
    expect(button).not_to be_disabled
    expect(page).to have_no_css('#busy-test[aria-busy]')
  end
end

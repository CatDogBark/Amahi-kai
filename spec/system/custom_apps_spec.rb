require 'rails_helper'

# Add your own app in a real browser (custom_apps.js): the two tabs, rows added and removed, the
# kernel permissions only for an app that runs as the image says, then the review and your
# password, and Install opening by itself on the Apps page; and a logo, shown as it's chosen.
RSpec.describe 'Apps of your own', type: :system do
  let(:custom) { Rails.root.join('tmp', 'custom-apps').to_s }

  before do
    allow(DockerService).to receive(:installed?).and_return(true)
    allow(DockerService).to receive(:running?).and_return(true)
    allow_any_instance_of(AppVersions).to receive(:pin) { |_versions, image| "#{image}@sha256:#{'7f3c' * 16}" }
    # The helper keeps the file it's given, as it would (outside production it isn't run)
    allow(Privileged).to receive(:call).and_call_original
    allow(Privileged).to receive(:call).with('apps.custom_save', any_args) do |_op, app:, manifest:, logo: nil|
      FileUtils.mkdir_p(custom)
      File.write("#{custom}/#{app}.yml", manifest)
      File.binwrite("#{custom}/#{app}.png", logo.unpack1('m0')) if logo.present?
      { 'app' => app, 'saved' => true }
    end
    FileUtils.rm_rf(custom)
    AppCatalog.reload!
  end

  after do
    FileUtils.rm_rf(custom)
    AppCatalog.reload!
  end

  # As production checks them: each form's token is for its own address, so a button that sends
  # another form's fields elsewhere is refused (Back did, found on the test VM)
  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it 'describes an app, reviews it, and adds it with your password' do
    sign_in_as_admin
    visit '/apps'
    within('#add-your-own') { click_link 'Add your own app' }
    expect(page).to have_button('Describe it')
    expect(page).to have_css('[data-custom-caps]', visible: :hidden)
    choose 'app[run_as]', option: 'image'
    expect(page).to have_text('Starting as root is riskier.')
    expect(page).to have_checked_field('app[capabilities][]', with: 'SETGID')
    choose 'app[run_as]', option: 'app'
    expect(page).to have_css('[data-custom-caps]', visible: :hidden)

    fill_in 'Name', with: 'Mealie'
    fill_in 'What it does, in a line', with: 'Recipes and meal plans'
    fill_in 'Image', with: 'ghcr.io/mealie-recipes/mealie:v2.4.1'
    first('[data-custom-rows="ports"] [data-custom-row]').fill_in('On the NAS', with: '9925')
    first('[data-custom-rows="ports"] [data-custom-row]').fill_in('In the app', with: '9000')
    click_button '+ Add a port'
    expect(page).to have_css('[data-custom-rows="ports"] [data-custom-row]', count: 2)
    all('[data-custom-rows="ports"] [data-custom-row]').last.find('[aria-label="Remove this port"]').click
    expect(page).to have_css('[data-custom-rows="ports"] [data-custom-row]', count: 1)
    click_button '+ Add a setting'
    setting = all('[data-custom-rows="settings"] [data-custom-row]').last
    setting.fill_in('Setting', with: 'ALLOW_SIGNUP')
    setting.fill_in('Value', with: 'false')
    setting.select("The NAS's time zone", from: 'Is')
    expect(setting).to have_css('[data-custom-value]', visible: :hidden)
    setting.select('A value', from: 'Is')

    click_button 'I have an app file'
    expect(page).to have_field('manifest')
    click_button 'Describe it'
    click_button 'Review'

    expect(page).to have_text('What it will be able to do')
    expect(page).to have_text('As its own user, with no kernel permissions')
    expect(page).to have_text("It isn't from the Amahi-kai catalog")
    # Back to the form, as it was described, and on to the review again
    click_button 'Back to describing it'
    expect(page).to have_field('Name', with: 'Mealie')
    expect(page).to have_field('Setting', with: 'ALLOW_SIGNUP')
    click_button 'Review'
    expect(page).to have_text('What it will be able to do')
    fill_in 'Your password, to add an app of your own', with: User::SEED_ADMIN_PASSWORD
    click_button 'Add it'

    # Mealie doesn't work with shares: Install opens the install window straight away
    expect(page).to have_css('#app-install-modal', visible: :visible)
    expect(page).to have_current_path('/apps') # ?install= is gone, so a reload doesn't open it again
  end

  it 'shows the logo chosen at once, on the review, then from the NAS on its card' do
    png = Rails.root.join('tmp', 'logo-spec.png')
    File.binwrite(png, 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='.unpack1('m0'))
    sign_in_as_admin
    visit '/apps/custom/new'
    fill_in 'Name', with: 'Mealie'
    fill_in 'Image', with: 'ghcr.io/mealie-recipes/mealie:v2.4.1'
    first('[data-custom-rows="ports"] [data-custom-row]').fill_in('On the NAS', with: '9925')
    first('[data-custom-rows="ports"] [data-custom-row]').fill_in('In the app', with: '9000')
    attach_file 'A picture, if you have one', png
    expect(page).to have_css('[data-custom-logo-preview] img.kai-app-logo[src^="data:image/png;base64,"]')
    click_button 'Review'

    expect(page).to have_css('.kai-custom-review-head img.kai-app-logo[src^="data:image/png;base64,"]')
    fill_in 'Your password, to add an app of your own', with: User::SEED_ADMIN_PASSWORD
    click_button 'Add it'
    expect(page).to have_css('#app-install-modal', visible: :visible)
    logo = find('#docker_app_mealie img.kai-app-logo', visible: :all)
    expect(logo[:src]).to match(%r{/apps/custom/mealie/logo\?v=\h{12}\z})
    expect(page.evaluate_script("document.querySelector('#docker_app_mealie img.kai-app-logo').naturalWidth")).to eq(1) # it loaded
  ensure
    FileUtils.rm_f(png)
  end
end

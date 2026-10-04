module SettingsHelper
  UPDATE_REPO = 'https://github.com/CatDogBark/Amahi-kai'.freeze

  # A change's title from the update check, its "(#NN)" linked to the pull request.
  def update_change_link(subject)
    match = subject.to_s.match(/\A(.*)\(#(\d+)\)\s*\z/)
    return subject.to_s unless match

    safe_join([match[1], link_to("##{match[2]}", "#{UPDATE_REPO}/pull/#{match[2]}", target: '_blank', rel: 'noopener')])
  end
end

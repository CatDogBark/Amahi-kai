module SettingsHelper
  UPDATE_REPO = 'https://github.com/CatDogBark/Amahi-kai'.freeze
  JOB_RESULTS = { ok: %w[OK bg-success], failed: %w[Failed bg-danger], running: ['Running', 'bg-info text-dark'],
                  off: %w[Off bg-secondary] }.freeze

  # How a scheduled job's last run went (ScheduledJobs::Job#result).
  def job_result_badge(job)
    label, css = JOB_RESULTS.fetch(job.result, ['Not run yet', 'bg-secondary'])
    content_tag(:span, label, class: "badge #{css}")
  end

  def job_last_run(job, capitalize: false)
    return(capitalize ? 'Not yet' : 'not yet') unless job.last_run
    relative_time_tag(job.last_run, capitalize: capitalize)
  end

  def job_next_run(job)
    job.next_run ? relative_time_tag(job.next_run, future: true) : 'not scheduled'
  end

  # The release key that signed the release on offer, for the System Update card and dialog; nothing
  # for the dev branch, which has no tags. A release that isn't signed is never on offer
  # (refused_release).
  def release_signature(update)
    return unless update.available? && update.tag && update.signed?

    content_tag(:p, "✓ Signed with #{update.signer_label}.", class: 'small mb-2 release-signature text-success')
  end

  # Why the check refused a newer release, in place of "Up to date": it isn't signed with a release
  # key, so System Update won't install it.
  def refused_release(update)
    why = " (#{update.refused_why})" if update.refused_why
    staying = update.current_version || update.short(update.current)
    content_tag(:p, class: 'mb-0 text-warning release-refused') do
      "⚠ Refused #{update.refused_tag}: it isn't signed with a release key#{why}. Amahi-kai stays on #{staying}."
    end
  end

  # A change's title from the update check, its "(#NN)" linked to the pull request.
  def update_change_link(subject)
    match = subject.to_s.match(/\A(.*)\(#(\d+)\)\s*\z/)
    return subject.to_s unless match

    safe_join([match[1], link_to("##{match[2]}", "#{UPDATE_REPO}/pull/#{match[2]}", target: '_blank', rel: 'noopener')])
  end

  # A changelog entry from the update check, its **bold** and `code` shown as such and
  # everything else escaped. Asterisks inside code are kept from starting bold text.
  def changelog_entry(text)
    html = ERB::Util.html_escape(text.to_s)
    html = html.gsub(/`([^`]+)`/) { "<code>#{Regexp.last_match(1).gsub('*', '&#42;')}</code>" }
    html.gsub(/\*\*(.+?)\*\*/) { "<strong>#{Regexp.last_match(1)}</strong>" }.html_safe # rubocop:disable Rails/OutputSafety
  end
end

module SettingsHelper
  UPDATE_REPO = 'https://github.com/CatDogBark/Amahi-kai'.freeze
  JOB_RESULTS = { ok: %w[OK bg-success], failed: %w[Failed bg-danger], running: ['Running', 'bg-info text-dark'] }.freeze

  # How a scheduled job's last run went (ScheduledJobs::Job#result).
  def job_result_badge(job)
    label, css = JOB_RESULTS.fetch(job.result, ['Not run yet', 'bg-secondary'])
    content_tag(:span, label, class: "badge #{css}")
  end

  def job_last_run(job)
    job.last_run ? "#{time_ago_in_words(job.last_run)} ago" : 'not yet'
  end

  def job_next_run(job)
    return 'not scheduled' unless job.next_run
    job.next_run > Time.current ? "in #{distance_of_time_in_words(Time.current, job.next_run)}" : 'any moment'
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

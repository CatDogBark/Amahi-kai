module ServersHelper
  STATE_BADGES = {
    'active' => %w[Running bg-success],
    'activating' => %w[Starting bg-info],
    'deactivating' => %w[Stopping bg-warning],
    'reloading' => %w[Reloading bg-info],
    'failed' => %w[Failed bg-danger]
  }.freeze

  # Bootstrap badge for a SystemServices::Service's state.
  def service_state_badge(service)
    return content_tag(:span, 'Idle', class: 'badge bg-info text-dark', title: service.idle_reason) if service.idle?
    label, css = service.installed? ? STATE_BADGES.fetch(service.state, %w[Stopped bg-secondary]) : ['Not installed', 'bg-secondary']
    content_tag(:span, label, class: "badge #{css}", title: [service.state, service.sub_state].compact.join(' / '))
  end

  # "1 day, 15 hours" — the two largest units, like the dashboard's uptime.
  def duration_words(seconds)
    return nil if seconds.nil?
    return 'under a minute' if seconds < 60
    parts = [[86_400, 'day'], [3600, 'hour'], [60, 'minute']].filter_map do |size, unit|
      count, seconds = seconds.divmod(size)
      pluralize(count, unit) if count.positive?
    end
    parts.first(2).join(', ')
  end
end

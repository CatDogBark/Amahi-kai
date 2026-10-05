module DisksHelper
  # A pool's or a pool drive's state as a badge: ONLINE green, DEGRADED yellow, anything else
  # (FAULTED, UNAVAIL, REMOVED, OFFLINE...) red.
  def pool_state_badge(state)
    css = case state
          when 'ONLINE' then 'bg-success'
          when 'DEGRADED' then 'bg-warning text-dark'
          else 'bg-danger'
          end
    content_tag(:span, state.presence || 'UNKNOWN', class: "badge #{css}")
  end

  HEALTH_BADGES = { ok: ['OK', 'bg-success'], warning: ['Check', 'bg-warning text-dark'], danger: ['Failing', 'bg-danger'] }.freeze

  # A drive's SMART health for the drive tables: a badge, its problems, then its wear, hours
  # and firmware. "—" for drives without SMART data (virtual disks, or not checked yet).
  def drive_health(health, path)
    details = health&.drive_details(path)
    return content_tag(:span, '—', class: 'text-muted') if details.nil?
    label, css = HEALTH_BADGES.fetch(health.drive_level(path))
    problems = health.drive_problems(health.drive(path)).map(&:last).join(', ').upcase_first
    safe_join([content_tag(:span, label, class: "badge #{css} me-1"), [problems.presence, details.presence].compact.join(' · ')], ' ')
  end

  # The badge alone, for Devices' card headers ("SMART OK"), or nil without SMART data.
  def drive_health_badge(health, path)
    return nil unless health&.drive(path)
    label, css = HEALTH_BADGES.fetch(health.drive_level(path))
    content_tag(:span, "SMART #{label}", class: "badge #{css} ms-2", title: health.drive_details(path))
  end

  # What a whole disk is used for, on Disks → ZFS Pools (StoragePools.drives' roles).
  def drive_role(drive)
    case drive[:role]
    when :os then 'System disk'
    when :share then "Share storage (#{drive[:mounts].join(', ')})"
    when :in_use then 'In use (LVM, RAID or encryption)'
    when :pool then "ZFS pool #{drive[:pool]}"
    when :old_zfs then "Free: has an old ZFS label (pool #{drive[:pool]}, not on this server), which a new pool erases"
    else 'Free'
    end
  end

  # A pool drive's by-id name without its bus prefix and partition: ata-Samsung_SSD_870_S6P-part1
  # → Samsung_SSD_870_S6P (the model and serial printed on the drive).
  def pool_drive_id(name)
    File.basename(name.to_s).sub(/\A(?:ata|nvme|scsi|wwn|virtio)-/, '').sub(/-part\d+\z/, '')
  end
end

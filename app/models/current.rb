# Per-request state. Rails keeps these attributes separate for each thread and
# clears them when a request finishes, so concurrent requests can't see each other's.
class Current < ActiveSupport::CurrentAttributes
  attribute :controller
end

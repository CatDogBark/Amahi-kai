module AmahiHDA
  module Routes
    # method for adding the routes for plugins
    def amahi_plugin_routes
      # Legacy plugin engines have been consolidated into the main app.
      # This method is kept as a no-op for backward compatibility.
    end
  end
end

# make the route plugin method available in the router
module ActionDispatch::Routing
  class Mapper
    include AmahiHDA::Routes
  end
end

json.status :ok
json.content render(partial: 'settings/server', formats: [:html], locals: { server: @server })

# Shared SSE (Server-Sent Events) streaming concern.
#
# Extracts the common boilerplate from streaming controller actions:
# - SSE response headers
# - Enumerator-based response body
# - sse_send helper for data + event messages
# - Automatic "done" event on completion
#
# Usage:
#
#   class MyController < ApplicationController
#     include SseStreaming
#
#     def install_stream
#       stream_sse do |sse|
#         sse.send("Starting installation...")
#         sse.send("Step 1 complete")
#         sse.send("success", event: "done")
#       end
#     end
#   end
#
module SseStreaming
  extend ActiveSupport::Concern

  private

  # Set up SSE headers and yield an SseSender for writing events.
  # The block receives an SseSender that responds to #send(data, event: nil).
  def stream_sse
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Last-Modified'] = Time.now.httpdate

    self.response_body = Enumerator.new do |yielder|
      sender = SseSender.new(yielder)
      yield sender
    end
  end

  # Lightweight wrapper around the Enumerator yielder for cleaner SSE output.
  class SseSender
    def initialize(yielder)
      @yielder = yielder
    end

    # Send an SSE message.
    #   send("Installing...") → data: Installing...\n\n
    #   send("success", event: "done") → event: done\ndata: success\n\n
    def send(data, event: nil)
      msg = ""
      msg += "event: #{event}\n" if event
      msg += "data: #{data}\n\n"
      @yielder << msg
    end

    # Convenience: send a "done" event with success/error status.
    def done(status = "success")
      send(status, event: "done")
      # Send padding to flush any buffering proxies/middleware
      @yielder << "\n"
    end

    # Convenience: send a step line (blue in terminal UI).
    def step(text)
      send(text)
    end

    # Convenience: send a success line.
    def success(text)
      send(text)
    end

    # Convenience: send an error line.
    def error(text)
      send(text)
    end

    # Stream output from a shell command line by line.
    def stream_command(cmd)
      IO.popen(cmd) do |io|
        io.each_line { |line| send("  #{line.chomp}") }
      end
      $?.success?
    end
  end
end

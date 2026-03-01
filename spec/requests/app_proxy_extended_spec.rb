require 'rails_helper'

RSpec.describe "AppProxy extended", type: :request do
  before { login_as_admin }

  let!(:docker_app) { create(:docker_app, identifier: 'proxytest', status: 'running', host_port: 8080) }

  describe "proxy request forwarding" do
    before do
      @mock_response = instance_double(Net::HTTPOK,
        code: '200',
        body: '<html><head><title>Test</title></head><body>Hello</body></html>',
        :[]=  => nil
      )
      allow(@mock_response).to receive(:[]).with('content-type').and_return('text/html')
      allow(@mock_response).to receive(:each_header).and_yield('x-custom', 'value')

      mock_http = instance_double(Net::HTTP)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:verify_mode=)
      allow(mock_http).to receive(:request).and_return(@mock_response)
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
    end

    it "proxies GET requests to the app" do
      get '/app/proxytest/dashboard'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Hello')
    end

    it "proxies POST requests" do
      post '/app/proxytest/api/data', params: { key: 'val' }
      expect(response).to have_http_status(:ok)
    end

    it "proxies PUT requests" do
      put '/app/proxytest/api/resource/1'
      expect(response).to have_http_status(:ok)
    end

    it "proxies DELETE requests" do
      delete '/app/proxytest/api/resource/1'
      expect(response).to have_http_status(:ok)
    end

    it "proxies PATCH requests" do
      patch '/app/proxytest/api/resource/1'
      expect(response).to have_http_status(:ok)
    end

    it "sets X-Forwarded headers" do
      expect_any_instance_of(Net::HTTP::Get).to receive(:[]=).with('X-Forwarded-For', anything).and_call_original
      expect_any_instance_of(Net::HTTP::Get).to receive(:[]=).with('X-Forwarded-Proto', anything).and_call_original
      get '/app/proxytest/'
    end

    it "forwards response headers from upstream" do
      get '/app/proxytest/'
      expect(response.headers['x-custom']).to eq('value')
    end
  end

  describe "error handling" do
    it "returns 503 when app is stopped" do
      app.update_column(:status, 'stopped')
      get '/app/proxytest/'
      expect(response).to have_http_status(:service_unavailable)
    end

    it "returns 503 when host_port is nil" do
      app.update_column(:host_port, nil)
      get '/app/proxytest/'
      expect(response).to have_http_status(:service_unavailable)
    end

    it "returns 404 for nonexistent app" do
      get '/app/doesnotexist/'
      expect(response).to have_http_status(:not_found)
    end

    it "returns 502 on connection refused" do
      mock_http = instance_double(Net::HTTP)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:verify_mode=)
      allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED)
      allow(Net::HTTP).to receive(:new).and_return(mock_http)

      get '/app/proxytest/'
      expect(response).to have_http_status(:bad_gateway)
    end

    it "returns 504 on timeout" do
      mock_http = instance_double(Net::HTTP)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:verify_mode=)
      allow(mock_http).to receive(:request).and_raise(Net::ReadTimeout)
      allow(Net::HTTP).to receive(:new).and_return(mock_http)

      get '/app/proxytest/'
      expect(response).to have_http_status(:gateway_timeout)
    end

    it "returns 502 on socket error" do
      mock_http = instance_double(Net::HTTP)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:verify_mode=)
      allow(mock_http).to receive(:request).and_raise(SocketError.new("getaddrinfo failed"))
      allow(Net::HTTP).to receive(:new).and_return(mock_http)

      get '/app/proxytest/'
      expect(response).to have_http_status(:bad_gateway)
    end
  end

  describe "HTML rewriting" do
    before do
      html = '<html><head><title>App</title></head><body><img src="/static/logo.png"></body></html>'
      mock_response = instance_double(Net::HTTPOK, code: '200', body: html)
      allow(mock_response).to receive(:[]).with('content-type').and_return('text/html')
      allow(mock_response).to receive(:each_header)

      mock_http = instance_double(Net::HTTP)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:verify_mode=)
      allow(mock_http).to receive(:request).and_return(mock_response)
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
    end

    it "injects base tag and rewrites root-absolute paths" do
      get '/app/proxytest/'
      expect(response.body).to include('<base href=')
      expect(response.body).to include('/app/proxytest/static/logo.png')
    end
  end

  describe "unauthenticated access" do
    it "redirects to login" do
      # Reset session
      reset!
      get '/app/proxytest/'
      expect(response).to redirect_to(new_user_session_url)
    end
  end
end

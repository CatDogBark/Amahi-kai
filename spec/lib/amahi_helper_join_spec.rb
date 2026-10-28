require 'rails_helper'
require 'open3'

# The root helper's source is libexec/amahi-helper and its parts (libexec/amahi-helper.d), one per
# area; it's installed as one file, with each part in place of the line that loads it
# (bin/amahi-join-helper), so the helper that runs as root loads only Ruby's standard library.
RSpec.describe 'bin/amahi-join-helper' do
  let(:entry) { Rails.root.join('libexec/amahi-helper').to_s }
  let(:listed) { File.read(entry).scan(%r{^require_relative 'amahi-helper\.d/([a-z0-9-]+)'$}).flatten }

  before(:all) { Privileged.operations } # loads the helper's source

  # Outside Bundler's environment, which would load gems into it (the self-test refuses them)
  def ruby(*args)
    Bundler.with_unbundled_env { Open3.capture3(RbConfig.ruby, '--disable-gems', *args) }
  end

  it 'runs with gems off, as everything root runs does' do
    expect(File.foreach(Rails.root.join('bin/amahi-join-helper')).first).to eq("#!/usr/bin/ruby --disable-gems\n")
    expect(File.executable?(Rails.root.join('bin/amahi-join-helper'))).to be(true)
  end

  it 'puts every part in place, in the order listed, and leaves nothing that loads another file' do
    joined = HelperSource.text
    expect(listed.first).to eq('core')
    expect(listed).to match_array(Dir[Rails.root.join('libexec/amahi-helper.d/*.rb')].map { |file| File.basename(file, '.rb') })
    expect(joined.scan(%r{^# ---- libexec/amahi-helper\.d/(\S+)\.rb ----$}).flatten).to eq(listed)
    expect(joined).not_to match(/^\s*(require_relative|load)\b/)
    listed.each do |part|
      expect(joined).to include(File.read(Rails.root.join("libexec/amahi-helper.d/#{part}.rb")).delete_prefix("# frozen_string_literal: true\n"))
    end
  end

  it 'makes a helper that passes its self-test and has the same operations' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'amahi-helper')
      File.write(path, HelperSource.text)
      _out, err, status = ruby('-c', path)
      expect(status).to be_success, err
      out, err, status = ruby(path, '--self-test')
      expect(status).to be_success, err
      expect(out).to eq("ok: #{AmahiHelper::OPERATIONS.size} operations\n")
      out, = ruby(path, '--list')
      expect(out.lines.map(&:chomp)).to match_array(AmahiHelper::OPERATIONS.keys)
    end
  end

  # A copy of bin/amahi-join-helper and libexec, changed by the block, joined
  def join_copy
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/bin")
      FileUtils.cp(Rails.root.join('bin/amahi-join-helper'), "#{dir}/bin/")
      FileUtils.cp_r(Rails.root.join('libexec'), dir)
      yield "#{dir}/libexec"
      return ruby("#{dir}/bin/amahi-join-helper")
    end
  end

  it "refuses a part that isn't there, one that isn't listed, and one that loads a file itself" do
    out, err, status = join_copy { |libexec| File.delete("#{libexec}/amahi-helper.d/dns.rb") }
    expect([status.exitstatus, out]).to eq([1, ''])
    expect(err).to include('amahi-helper.d/dns.rb isn\'t there')

    _out, err, status = join_copy { |libexec| File.write("#{libexec}/amahi-helper.d/extra.rb", "module AmahiHelper\nend\n") }
    expect(status.exitstatus).to eq(1)
    expect(err).to include('not listed in libexec/amahi-helper: extra')

    _out, err, status = join_copy { |libexec| File.write("#{libexec}/amahi-helper.d/dns.rb", "require_relative 'elsewhere'\n", mode: 'a') }
    expect(status.exitstatus).to eq(1)
    expect(err).to include("dns.rb loads a file itself (require_relative 'elsewhere')")
  end
end

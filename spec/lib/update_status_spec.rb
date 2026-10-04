require 'rails_helper'

RSpec.describe UpdateStatus do
  let(:path) { Rails.root.join('tmp', "update-status-spec-#{Process.pid}.json").to_s }

  after { FileUtils.rm_f(path) }

  def write(data)
    File.write(path, JSON.generate(data))
  end

  it 'reads an available update' do
    write('checked_at' => '2026-10-04T20:00:00Z', 'current' => 'aaaaaaa111', 'latest' => 'bbbbbbb222',
          'available' => true, 'behind' => 2, 'error' => nil,
          'commits' => [{ 'sha' => 'bbbbbbb', 'subject' => 'Thing (#36)' }, 'junk'],
          'changelog' => ['- **A fix.**', 42])
    status = described_class.load(path)
    expect(status).to be_checked
    expect(status).to be_available
    expect(status.behind).to eq(2)
    expect(status.short(status.latest)).to eq('bbbbbbb')
    expect(status.commits).to eq([{ 'sha' => 'bbbbbbb', 'subject' => 'Thing (#36)' }])
    expect(status.changelog).to eq(['- **A fix.**'])
    expect(status.checked_at).to eq(Time.utc(2026, 10, 4, 20))
  end

  it 'is up to date when nothing is behind, whatever the file claims' do
    write('checked_at' => '2026-10-04T20:00:00Z', 'available' => true, 'behind' => 0)
    expect(described_class.load(path)).not_to be_available
  end

  it 'is unchecked when the file is missing or unreadable' do
    expect(described_class.load(path)).not_to be_checked
    File.write(path, '{not json')
    status = described_class.load(path)
    expect(status).not_to be_checked
    expect(status).not_to be_available
  end
end

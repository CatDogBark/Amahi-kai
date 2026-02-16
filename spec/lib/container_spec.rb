require 'spec_helper'
require 'container'

RSpec.describe Container do
  let(:mock_container) { double('Docker::Container', kill: true, remove: true) }

  describe '#initialize' do
    it 'finds container by id' do
      allow(Docker::Container).to receive(:get).with('test-id').and_return(mock_container)
      c = Container.new('test-id')
      expect(c.instance_variable_get(:@container)).to eq(mock_container)
    end

    it 'sets @container to nil when container not found' do
      allow(Docker::Container).to receive(:get).and_raise(Docker::Error::NotFoundError)
      c = Container.new('missing-id')
      expect(c.instance_variable_get(:@container)).to be_nil
    end
  end

  describe '#create' do
    before do
      allow(Docker::Container).to receive(:get).and_raise(Docker::Error::NotFoundError)
    end

    it 'raises when image not found' do
      allow(Docker::Image).to receive(:get).and_return(nil)
      c = Container.new('myapp', { image: 'amahi/myapp', port: 8080, volume: '/tmp' })
      expect { c.create }.to raise_error(RuntimeError, /Image amahi\/myapp not found/)
    end

    it 'succeeds with valid image' do
      mock_image = double('Docker::Image')
      new_container = double('Docker::Container', start: true)
      allow(Docker::Image).to receive(:get).and_return(mock_image)
      allow(Docker::Container).to receive(:create).and_return(new_container)

      c = Container.new('myapp', { image: 'amahi/myapp', port: 8080, volume: '/tmp' })
      expect(c.create).to eq(true)
    end
  end

  describe '#remove' do
    it 'calls kill and remove on container' do
      allow(Docker::Container).to receive(:get).with('test-id').and_return(mock_container)
      c = Container.new('test-id')

      expect(mock_container).to receive(:kill)
      expect(mock_container).to receive(:remove)
      c.remove
    end
  end
end

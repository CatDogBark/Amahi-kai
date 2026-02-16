require 'spec_helper'

# Test the obfuscate/unobfuscate methods from ApplicationController
# by instantiating a test controller instance.
RSpec.describe "Credential Encryption" do
  let(:controller) { ApplicationController.new }

  describe "#obfuscate" do
    it "returns blank for blank input" do
      expect(controller.send(:obfuscate, "")).to eq("")
      expect(controller.send(:obfuscate, nil)).to be_nil
    end

    it "prefixes encrypted values with enc:" do
      result = controller.send(:obfuscate, "secret")
      expect(result).to start_with("enc:")
    end

    it "produces different output than input" do
      result = controller.send(:obfuscate, "mypassword")
      expect(result).not_to eq("mypassword")
    end
  end

  describe "#unobfuscate" do
    it "returns blank for blank input" do
      expect(controller.send(:unobfuscate, "")).to eq("")
      expect(controller.send(:unobfuscate, nil)).to be_nil
    end

    it "decrypts enc:-prefixed values" do
      encrypted = controller.send(:obfuscate, "secret123")
      decrypted = controller.send(:unobfuscate, encrypted)
      expect(decrypted).to eq("secret123")
    end

    it "round-trips correctly" do
      original = "p@ssw0rd!#$%"
      expect(controller.send(:unobfuscate, controller.send(:obfuscate, original))).to eq(original)
    end

    it "falls back to ROT13 for legacy values" do
      # ROT13 of "hello" is "uryyb"
      expect(controller.send(:unobfuscate, "uryyb")).to eq("hello")
    end

    it "decodes legacy ROT13 for non-prefixed values" do
      # ROT13 of "secret" is "frperg"
      expect(controller.send(:unobfuscate, "frperg")).to eq("secret")
    end

    it "returns empty string for corrupted encrypted data" do
      result = controller.send(:unobfuscate, "enc:garbage_data_here")
      expect(result).to eq("")
    end
  end

  describe "encryption strength" do
    it "produces different ciphertext for same plaintext (nonce-based)" do
      e1 = controller.send(:obfuscate, "same")
      e2 = controller.send(:obfuscate, "same")
      expect(e1).not_to eq(e2)
    end
  end
end

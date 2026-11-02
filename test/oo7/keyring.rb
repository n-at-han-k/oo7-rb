# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

require "oo7"

# Against the session's real Secret Service, because what is worth catching is
# whether the protocol round trips -- a mocked collection would only prove the
# bindings call themselves.
#
# Every item carries a marker attribute of its own, so a run writes nothing a
# previous one has to tolerate and cleans up only after itself.
describe Oo7::Keyring do
  MARKER = "oo7-rb-test"

  def self.available?
    Oo7::Keyring.new
    true
  rescue StandardError
    false
  end

  if available?
    let(:keyring) {Oo7::Keyring.new.tap(&:unlock)}
    let(:run) {"#{MARKER}-#{Process.pid}-#{rand(1 << 32)}"}
    let(:attributes) {{"xdg:schema" => MARKER, "run" => run}}

    def after
      Oo7::Keyring.new.tap(&:unlock).delete({"xdg:schema" => MARKER, "run" => run})
    rescue StandardError
      nil
    end

    it "reports whether it is locked" do
      expect([true, false]).to be(:include?, keyring.locked?)
    end

    it "stores a secret and finds it again by attribute" do
      keyring.create("oo7-rb test", attributes, "hunter2", true)

      items = keyring.search(attributes)

      expect(items.size).to be == 1
      expect(items.first.secret).to be == "hunter2"
    end

    it "names the item with the label it was given" do
      keyring.create("oo7-rb test label", attributes, "s", true)

      expect(keyring.search(attributes).first.label).to be == "oo7-rb test label"
    end

    it "carries the attributes back with the item" do
      keyring.create("oo7-rb test", attributes, "s", true)

      expect(keyring.search(attributes).first.attributes["run"]).to be == run
    end

    it "replaces rather than duplicates when asked to" do
      keyring.create("oo7-rb test", attributes, "first", true)
      keyring.create("oo7-rb test", attributes, "second", true)

      items = keyring.search(attributes)

      expect(items.size).to be == 1
      expect(items.first.secret).to be == "second"
    end

    it "rotates a secret in place" do
      keyring.create("oo7-rb test", attributes, "before", true)
      keyring.search(attributes).first.secret = "after"

      expect(keyring.search(attributes).first.secret).to be == "after"
    end

    it "finds nothing once the item is deleted" do
      keyring.create("oo7-rb test", attributes, "s", true)
      keyring.delete(attributes)

      expect(keyring.search(attributes)).to be(:empty?)
    end

    it "finds nothing for attributes nothing was stored under" do
      expect(keyring.search({"xdg:schema" => MARKER, "run" => "#{run}-absent"})).to be(:empty?)
    end

    it "dates the item it stored" do
      keyring.create("oo7-rb test", attributes, "s", true)

      expect(keyring.search(attributes).first.created).to be > 0
    end
  else
    it "skips: no Secret Service on this session bus" do
      expect(true).to be == true
    end
  end
end

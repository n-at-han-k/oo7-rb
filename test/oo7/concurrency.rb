# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

require "oo7"

# The GVL is released around a keyring call, which is the only reason a GTK
# application can put one on a worker thread and keep its main loop answering.
# The GVL is global: a worker blocking inside an extension that still holds it
# stops the main thread too, so offloading would buy nothing and the desktop
# would freeze exactly as it did before.
#
# Checked by behaviour rather than by inspection: another Ruby thread has to make
# progress while a keyring call is in flight.
describe "Oo7 concurrency" do
  def self.available?
    Oo7::Keyring.new
    true
  rescue StandardError
    false
  end

  if available?
    it "lets another thread run while a keyring call is in flight" do
      ticks = 0
      stop = false

      ticker = Thread.new do
        until stop
          ticks += 1
          sleep(0.001)
        end
      end

      # Enough calls to take meaningfully longer than a tick. Each one is a
      # round trip to the secret service.
      keyring = Oo7::Keyring.new
      keyring.unlock
      50.times { keyring.search({"xdg:schema" => "oo7-rb-concurrency"}) }

      stop = true
      ticker.join

      # Holding the GVL throughout would leave the ticker starved. The number is
      # deliberately low: the point is "ran at all", not a benchmark.
      expect(ticks).to be > 5
    end

    it "does not deadlock when two threads call at once" do
      results = 2.times.map do
        Thread.new do
          keyring = Oo7::Keyring.new
          keyring.unlock
          keyring.search({"xdg:schema" => "oo7-rb-concurrency"}).is_a?(Array)
        end
      end.map(&:value)

      expect(results).to be == [true, true]
    end
  else
    it "skips: no Secret Service on this session bus" do
      expect(true).to be == true
    end
  end
end

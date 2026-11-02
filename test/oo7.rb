# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

require "oo7"

describe Oo7 do
  it "defines every class the crate's init names" do
    expect([:Keyring, :Item] - Oo7.constants).to be(:empty?)
  end

  it "has a version" do
    expect(Oo7::VERSION).to be =~ /\A\d+\.\d+\.\d+/
  end
end

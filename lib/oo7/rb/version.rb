# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

# This sits at lib/oo7/rb/version.rb rather than lib/oo7/version.rb because
# gem_kit-release derives the path from the gem name -- "oo7-rb" nests as
# oo7/rb -- and `gem kit bump` rewrites the literal here. The constant is still
# Oo7::VERSION: gem_kit only cares which file it is, not what module is in it.
module Oo7
  VERSION = "1.0.1"
end

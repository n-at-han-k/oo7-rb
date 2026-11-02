# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

# The gem is `oo7-rb` because RubyGems holds `oo7` for an unrelated `OO7`, and
# a name differing only in case cannot be taken once the other has indexed
# versions. The library is still `oo7`: `require "oo7"` is the one to write.
#
# This file exists so that `gem "oo7-rb"` in a Gemfile needs no `require:` of
# its own -- Bundler.require derives the path from the gem name, and would
# otherwise look for a file that is not here.
require_relative "oo7"

# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

require_relative "oo7/version"

# The native extension, which is where every class in this module is defined.
#
# A precompiled platform gem carries one object per Ruby ABI, which rake-compiler puts under lib/oo7/3.3, 3.4 and so on. The source gem compiles one object and installs it beside the library, which is also where `rake compile` puts it.
begin
  require_relative "oo7/#{RUBY_VERSION[/\d+\.\d+/]}/oo7"
rescue LoadError
  require_relative "oo7/oo7"
end

# Ruby bindings for oo7, the Rust Secret Service and keyring implementation.
#
# The crate speaks the freedesktop Secret Service D-Bus protocol itself and does its own crypto, so a caller here never loads libsecret, gnome-keyring's client library or libgcr.
#
# Every method is synchronous. The crate's API is async throughout; the extension drives it on a Tokio runtime of its own and blocks the calling thread, which is what a Ruby caller expects. The GVL is held while it waits, so a call that may prompt belongs on a Ruby thread rather than on a GTK main loop.
module Oo7
end

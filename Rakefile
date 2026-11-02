# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

require "rb_sys/extensiontask"

GEMSPEC = Gem::Specification.load("oo7.gemspec")

# Compiles ext/oo7, the Rust crate over oo7, into lib/oo7/oo7.so.
#
# Nothing else is in this gem: lib/oo7.rb requires the object and names the module, and every class belongs to the crate's #[magnus::init].
#
# RbSys::ExtensionTask rather than the plain Rake::ExtensionTask, because it wires up the rb-sys toolchain which cross-compiles precompiled per-platform gems. That is what lets `gem install oo7` want no Rust: RubyGems serves the gem matching the platform, whose object is already built, rather than the source gem which shells out to cargo.
RbSys::ExtensionTask.new("oo7", GEMSPEC) do |ext|
  ext.ext_dir = "ext/oo7"
  ext.lib_dir = "lib/oo7"

  # A precompiled gem carries one object per Ruby version, under lib/oo7/3.3, 3.4 and so on.
  ext.cross_compile = true
end

# Cross-compile one platform's gem inside the rb-sys-dock container, as `rake native[x86_64-linux]`. CI drives the whole matrix through oxidize-rb/actions/cross-gem: see .github/workflows/cross-compile.yml.
task :native, [:platform] do |_task, arguments|
  platform = arguments[:platform] or abort "usage: rake native[<platform>]"

  sh "bundle", "exec", "rb-sys-dock", "--platform", platform, "--build"
end

task default: :compile

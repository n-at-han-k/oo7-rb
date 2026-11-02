{
  description = "oo7 — GTK4 example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, utils, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Its own shell rather than the repository's: that one carries the Rust
        # toolchain and rb-sys to build the extension, and none of the GTK stack.
        # This one is the other way round. The extension is built there and loaded
        # here over RUBYLIB.
        gems = pkgs.bundlerEnv {
          name = "oo7-gtk-example-gems";
          ruby = pkgs.ruby_3_4;
          gemfile = ./Gemfile;
          lockfile = ./Gemfile.lock;
          gemset = import ./gemset.nix;
        };

        # gtk4 is introspection bindings, so the libraries and their typelibs have
        # to be found at runtime as well as at build time.
        gtkStack = with pkgs; [
          glib
          gobject-introspection
          gtk4
          gdk-pixbuf
          pango
          cairo
          harfbuzz
          graphene
          at-spi2-core
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ gems gems.wrappedRuby ] ++ gtkStack;

          shellHook = /* bash */ ''
            export GI_TYPELIB_PATH="${pkgs.lib.makeSearchPath "lib/girepository-1.0" gtkStack}"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath gtkStack}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

            # `require "oo7"` from the repository's own lib, where `rake compile`
            # puts the built object. Run that first, in the root shell.
            root="$(cd "$PWD/../.." && pwd)"
            export RUBYLIB="$root/lib''${RUBYLIB:+:$RUBYLIB}"

            export BUNDLE_GEMFILE="$PWD/Gemfile"
            export BUNDLE_FROZEN=false

            echo "oo7 GTK example. Build the extension first if you have not:"
            echo "  (cd $root && nix develop --command rake compile)"
            echo "Then: ruby main.rb"
          '';
        };
      }
    );
}

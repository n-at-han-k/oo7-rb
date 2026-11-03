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

        # The pkg-config gem resolves Requires.private transitively and hard-fails
        # on any missing .pc, so gtk4's whole private closure has to be here too.
        # Without it cairo-gobject's extconf dies in required_pkg_config_package
        # before anything is compiled.
        privateClosure = with pkgs; [
          fontconfig freetype libepoxy libpng libxkbcommon pcre2 util-linux wayland
          zlib fribidi libdatrie libthai libselinux libsepol expat brotli bzip2
          graphite2 icu libffi libxml2 lerc libdeflate xz zstd
          libsysprof-capture libwebp libpthread-stubs vulkan-loader systemd
          libtiff libjpeg libavif libgcrypt libgpg-error
          libx11 libxau libxcursor libxdmcp libxext libxfixes libxi libxinerama
          libxrandr libxrender libxcb xorgproto
        ];

        # nixpkgs' defaultGemConfig only carries entries for the GTK3-era
        # ruby-gnome gems, so the GTK4 ones get their build inputs here or they
        # fail to compile their extensions.
        rubyGnomeGem = _attrs: {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack ++ privateClosure;
        };

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

          gemConfig = pkgs.defaultGemConfig // {
            gdk4 = rubyGnomeGem;
            gsk4 = rubyGnomeGem;
            gtk4 = rubyGnomeGem;
            graphene1 = rubyGnomeGem;
            cairo-gobject = rubyGnomeGem;
            pango = rubyGnomeGem;
            atk = rubyGnomeGem;
            gdk_pixbuf2 = rubyGnomeGem;
            gio2 = rubyGnomeGem;
            glib2 = rubyGnomeGem;
          };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ gems gems.wrappedRuby ] ++ gtkStack;

          shellHook = /* bash */ ''
            # glib's first output is `bin`, which carries no typelibs, so
            # makeSearchPath over the derivations themselves finds nothing and
            # gio2 dies on "Typelib file for namespace 'Gio' not found". Hence
            # `.out`.
            export GI_TYPELIB_PATH="${pkgs.lib.makeSearchPath "lib/girepository-1.0" (map (drv: drv.out or drv) gtkStack)}"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (map (drv: drv.out or drv) gtkStack)}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

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

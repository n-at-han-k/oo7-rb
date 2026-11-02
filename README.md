# oo7-rb

Ruby bindings for [oo7](https://github.com/bilelmoussaoui/oo7), the Rust
implementation of the freedesktop [Secret
Service](https://specifications.freedesktop.org/secret-service-spec/) — the
API behind GNOME Keyring and KWallet.

## Why not libsecret

libsecret reaches the keyring through gnome-keyring's client library and
libgcr, whose `gcr_secret_exchange` carries a secret back from an unlock
prompt. oo7 speaks the D-Bus protocol itself and does its own cryptography, so
a caller here loads neither.

That matters when a bug in those libraries is not yours to fix. A plain
`OpenSession` should not be able to abort the process that made it, or the
shell that prompted for it, but when it can, the way out is to stop going
through them.

## Installation

```ruby
gem "oo7-rb"
```

The gem is `oo7-rb`; the library is `oo7`. RubyGems holds the name `oo7` for an
unrelated `OO7`, and a name differing only in case cannot be taken once the
other has indexed versions -- so the gem took the repository's name instead.
`require "oo7"` is the one to write, and `require "oo7-rb"` also works so that
`Bundler.require` needs no `require:` of its own.

## Usage

```ruby
require "oo7"

keyring = Oo7::Keyring.new
keyring.unlock

keyring.create("My app: nathan on example.com", {
  "xdg:schema" => "com.example.App",
  "server" => "example.com",
  "user" => "nathan",
}, "the-secret", true)

item = keyring.search({"xdg:schema" => "com.example.App", "user" => "nathan"}).first
item.secret        # => "the-secret"
item.label         # => "My app: nathan on example.com"
item.attributes    # => {"xdg:schema" => "com.example.App", ...}
```

`create`'s last argument replaces any item with the same attributes, which is
what keeps a rotated secret one item rather than a pile of them.

### Keyring

`new`, `unlock`, `lock`, `locked?`, `items`, `search(attributes)`,
`create(label, attributes, secret, replace)`, `delete(attributes)`.

`Keyring.new` picks the backend the way the crate does: the file backend when
the process is sandboxed, the D-Bus Secret Service otherwise.

### Item

`label`, `label=`, `attributes`, `attributes=`, `secret`, `secret=`, `locked?`,
`lock`, `unlock`, `delete`, `created`, `modified`.

## Blocking

Every method on the crate is async. Each binding drives it to completion on a
Tokio runtime owned by the extension and returns the result, so the Ruby API is
ordinary and synchronous.

The calling thread blocks and the GVL is held while it waits. A call that may
raise a prompt therefore belongs on a Ruby thread rather than on a GTK main
loop — otherwise the loop that owes the prompt a reply is the one being
blocked.

## Development

```
bin/test                      # compile the extension, run the suite
bin/test --skip-compile       # suite only
```

The suite runs against the session's real Secret Service and skips itself when
there isn't one. Items are written under an `xdg:schema` of `oo7-rb-test` with
a per-run marker, and removed afterwards.

## Licence

Apache-2.0. The oo7 crate itself is MIT.

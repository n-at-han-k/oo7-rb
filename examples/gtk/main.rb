# frozen_string_literal: true

# Released under the Apache License, Version 2.0.
# Copyright, 2026, by General Intelligence Systems.

# A secret stored, read and deleted from a GTK window, without the window ever
# stopping.
#
# Every Secret Service call is a round trip to another process, and some of them
# wait a long time -- a locked collection, a slow daemon, a prompt the user has
# not answered. Making one on the main loop is a window that has stopped drawing,
# and when the thing being waited on is itself waiting on the shell, the whole
# desktop stops. So the work goes on a thread, and only the widget update comes
# back to the main loop through GLib::Idle.
#
# Two things have to be true for that to be worth anything, and this file is the
# demonstration of the second:
#
#   1. The call is not on the main thread.  That part is ordinary GTK practice:
#      https://docs.gtk.org/gtk4/section-threading.html
#
#   2. The extension releases the GVL while it waits.  The GVL is global, so a
#      worker thread that blocks while holding it stops the main thread as surely
#      as calling on the main thread would. oo7 releases it (see
#      test/oo7/concurrency.rb); an extension that does not would make the thread
#      above pure decoration.
#
# The ticking counter is the evidence. It is driven by a GLib timeout on the main
# loop, so it only advances while that loop is running. Press a button and watch
# it keep going.
#
# Run: see ../../README.md, or `nix develop` here then `ruby main.rb`.

require "gtk4"
require "oo7"

# This example's own corner of the keyring, so it cannot see or disturb anything
# else stored on the system.
SCHEMA = "com.example.Oo7Example"

class Example
  def build
    app.tap do
      app.signal_connect("activate") do
        app.add_window(window)

        window.tap do |win|
          win.title = "oo7 — Secret Service from GTK"
          win.set_default_size(520, 320)
          win.child = layout
        end

        layout.tap do |box|
          box.append(heading)
          box.append(secret_entry)
          box.append(buttons)
          box.append(status)
          box.append(ticker)

          buttons.tap do |row|
            row.append(store_button)
            row.append(load_button)
            row.append(delete_button)

            store_button.signal_connect("clicked") { store }
            load_button.signal_connect("clicked") { load }
            delete_button.signal_connect("clicked") { delete }
          end
        end

        tick

        window.present
      end
    end
  end

  private

    # --- the keyring, always on a thread ------------------------------------

    # The shape every button below uses: name what is happening, do the waiting
    # on a thread, and come back to the main loop to say how it went.
    #
    # Nothing inside the block may touch a widget: GTK is callable from the main
    # thread only, which is what GLib::Idle.add is for -- it schedules the block
    # back onto the main loop.
    def keyring(doing, &work)
      say("#{doing}…")
      busy(true)

      Thread.new do
        outcome =
          begin
            work.call(collection)
          rescue StandardError => e
            # Carried rather than raised: an exception in a thread nobody joins is
            # an exception nobody sees.
            "#{e.class}: #{e.message}"
          end

        GLib::Idle.add do
          busy(false)
          say(outcome)
          false
        end
      end
    end

    # Opened once, on whichever thread gets there first, and unlocked as its own
    # step before anything is read -- the order fractal uses.
    def collection
      @collection ||= Oo7::Keyring.new.tap(&:unlock)
    end

    def attributes = { "xdg:schema" => SCHEMA, "account" => "demo" }

    def store
      secret_entry.text.then do |secret|
        keyring("Storing") do |keyring|
          keyring.create("oo7 example: demo", attributes, secret, true)
          "Stored #{secret.length} character(s)."
        end
      end
    end

    def load
      keyring("Reading") do |keyring|
        keyring.search(attributes).first.then do |item|
          if item
            item.unlock
            "Read back: #{item.secret.inspect} (label #{item.label.inspect})"
          else
            "Nothing stored yet."
          end
        end
      end
    end

    def delete
      keyring("Deleting") do |keyring|
        keyring.delete(attributes)
        "Deleted."
      end
    end

    # --- main loop ----------------------------------------------------------

    def say(text) = status.label = text

    def busy(working)
      @working = working
      [store_button, load_button, delete_button].each { |button| button.sensitive = !working }
    end

    # The proof. A timeout on the main loop, so it stops the moment that loop
    # does -- which is exactly what a keyring call on the main thread would do.
    def tick
      @ticks = 0

      GLib::Timeout.add(100) do
        @ticks += 1
        ticker.label = "main loop: #{@ticks} ticks#{@working ? " (keyring call in flight)" : ""}"
        true
      end
    end

    # --- widgets ------------------------------------------------------------

    def app = @app ||= Gtk::Application.new("com.example.Oo7Example", :default_flags)

    def window = @window ||= Gtk::ApplicationWindow.new(app)

    def layout
      @layout ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.margin_top = 18
        box.margin_bottom = 18
        box.margin_start = 18
        box.margin_end = 18
      end
    end

    def heading
      @heading ||= Gtk::Label.new.tap do |label|
        label.markup = "<b>A secret in the system keyring</b>\n" \
                       "<small>Every call below runs on a thread, so this window never stops.</small>"
        label.justify = :center
        label.wrap = true
      end
    end

    def secret_entry
      @secret_entry ||= Gtk::Entry.new.tap do |entry|
        entry.text = "hunter2"
        entry.placeholder_text = "the secret to store"
      end
    end

    def buttons
      @buttons ||= Gtk::Box.new(:horizontal, 8).tap do |box|
        box.homogeneous = true
      end
    end

    def store_button = @store_button ||= Gtk::Button.new(label: "Store")

    def load_button = @load_button ||= Gtk::Button.new(label: "Read back")

    def delete_button = @delete_button ||= Gtk::Button.new(label: "Delete")

    def status
      @status ||= Gtk::Label.new("Ready.").tap do |label|
        label.wrap = true
        label.selectable = true
      end
    end

    def ticker
      @ticker ||= Gtk::Label.new("main loop: 0 ticks").tap do |label|
        label.add_css_class("dim-label")
      end
    end
end

Example.new.build.run([])

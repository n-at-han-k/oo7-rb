//! Ruby bindings for oo7, the Rust Secret Service implementation, via magnus.
//!
//! The point of this binding is what it does *not* load. libsecret reaches the
//! keyring through gnome-keyring's client library and libgcr, whose
//! secret-exchange carries the secret back from an unlock prompt. oo7 speaks the
//! freedesktop Secret Service D-Bus protocol itself and does its own
//! cryptography (`native_crypto`), so none of that is in the address space.
//!
//! `Oo7::Keyring` is the collection, `Oo7::Item` one stored secret. The crate
//! picks its own backend in `Keyring::new`: the file backend when the process is
//! sandboxed, the D-Bus Secret Service otherwise.
//!
//! # Blocking
//!
//! Every method on the crate is async. Each binding drives it to completion on a
//! Tokio runtime owned by this extension and returns the result, so the Ruby API
//! is ordinary and synchronous.
//!
//! The calling thread waits, but it waits with the GVL released, so every other
//! Ruby thread keeps running. That is what lets a GTK application put a keyring
//! call on a worker thread and keep its main loop answering: without it the
//! worker would hold the GVL throughout and freeze the main thread anyway, which
//! is a frozen desktop rather than a slow one.
//!
//! # Provenance
//!
//! The oo7 crate is MIT licensed. Fractal is worth reading for how a client
//! sequences these calls -- unlock the collection, search, unlock each item --
//! but it is GPL-3.0-or-later, so nothing is copied from it into this file.
//!
//!   - <https://github.com/bilelmoussaoui/oo7> (MIT)
//!   - <https://gitlab.gnome.org/World/fractal> (GPL-3.0-or-later; read only)

use std::collections::HashMap;
use std::ffi::c_void;
use std::future::Future;
use std::sync::OnceLock;

use magnus::{function, method, prelude::*, Error, RArray, RHash, Ruby};

use oo7_core::{Item as CoreItem, Keyring as CoreKeyring, Secret as CoreSecret};
use tokio::runtime::{Builder, Runtime};

// --- helpers ---------------------------------------------------------------

fn rt_err<E: std::fmt::Display>(e: E) -> Error {
    // Safe: every caller runs inside a Ruby method invocation (GVL held).
    let ruby = Ruby::get().expect("rt_err called outside the Ruby VM");
    Error::new(ruby.exception_runtime_error(), e.to_string())
}

/// One runtime for the whole extension, built on first use.
///
/// A current-thread runtime is enough -- every call blocks on a single future --
/// but zbus spawns its own socket reader task, so the runtime has to keep
/// driving background work while we wait. Hence the multi-thread flavour with
/// one worker.
fn runtime() -> Result<&'static Runtime, Error> {
    static RUNTIME: OnceLock<std::io::Result<Runtime>> = OnceLock::new();

    RUNTIME
        .get_or_init(|| Builder::new_multi_thread().worker_threads(1).enable_all().build())
        .as_ref()
        .map_err(rt_err)
}

// Ruby's public C API, which magnus 0.9 does not bind (its list carries
// rb_thread_call_without_gvl commented out). Declared here rather than reached
// for through rb-sys' generated bindings, which depend on what bindgen picked up
// from this Ruby's headers.
unsafe extern "C" {
    fn rb_thread_call_without_gvl(
        func: extern "C" fn(*mut c_void) -> *mut c_void,
        data1: *mut c_void,
        ubf: Option<extern "C" fn(*mut c_void)>,
        data2: *mut c_void,
    ) -> *mut c_void;
}

/// Run `work` with the GVL released.
///
/// This is the whole reason a Ruby thread can be used to keep a keyring call off
/// a GTK main loop. The GVL is global: a worker thread that blocks inside an
/// extension still holding it stops every other Ruby thread, the main one
/// included, so offloading the call would otherwise buy nothing at all.
///
/// `work` must not touch Ruby -- no values, no exceptions, no allocation through
/// the VM -- because this thread does not hold the GVL while it runs. Driving a
/// future over D-Bus touches only Rust, which is what makes it eligible.
///
/// The unblocking function is None, so the call is not interruptible: a D-Bus
/// round trip that never answers cannot be killed by Thread#kill. That is the
/// trade for not blocking the VM, and it is the right way round for a UI, where
/// the alternative is a frozen desktop.
fn without_gvl<F, T>(work: F) -> T
where
    F: FnOnce() -> T,
{
    struct Payload<F, T> {
        work: Option<F>,
        out: Option<T>,
    }

    extern "C" fn call<F, T>(data: *mut c_void) -> *mut c_void
    where
        F: FnOnce() -> T,
    {
        // Safe: the pointer is the Payload below, alive for the whole call, and
        // reached from this one thread only.
        let payload = unsafe { &mut *data.cast::<Payload<F, T>>() };
        let work = payload.work.take().expect("the work runs once");
        payload.out = Some(work());
        std::ptr::null_mut()
    }

    let mut payload = Payload { work: Some(work), out: None };

    unsafe {
        rb_thread_call_without_gvl(
            call::<F, T>,
            (&raw mut payload).cast::<c_void>(),
            None,
            std::ptr::null_mut(),
        );
    }

    payload.out.expect("the work ran")
}

fn block<F: Future>(future: F) -> Result<F::Output, Error> {
    let runtime = runtime()?;

    Ok(without_gvl(|| runtime.block_on(future)))
}

/// A Ruby hash of strings, which is what the Secret Service calls attributes.
fn attributes_from(hash: RHash) -> Result<HashMap<String, String>, Error> {
    let mut attributes = HashMap::new();

    hash.foreach(|key: String, value: String| {
        attributes.insert(key, value);
        Ok(magnus::r_hash::ForEach::Continue)
    })?;

    Ok(attributes)
}

fn attributes_to(ruby: &Ruby, attributes: HashMap<String, String>) -> Result<RHash, Error> {
    let hash = ruby.hash_new();

    for (key, value) in attributes {
        hash.aset(key, value)?;
    }

    Ok(hash)
}

// --- Keyring ---------------------------------------------------------------

#[magnus::wrap(class = "Oo7::Keyring", free_immediately, size)]
struct Keyring(CoreKeyring);

impl Keyring {
    /// The default collection, over whichever backend the crate chooses.
    fn new() -> Result<Self, Error> {
        block(CoreKeyring::new())?.map(Keyring).map_err(rt_err)
    }

    /// Unlock the collection. A prompt is the service's business, not ours.
    fn unlock(&self) -> Result<(), Error> {
        block(self.0.unlock())?.map_err(rt_err)
    }

    fn lock(&self) -> Result<(), Error> {
        block(self.0.lock())?.map_err(rt_err)
    }

    fn is_locked(&self) -> Result<bool, Error> {
        block(self.0.is_locked())?.map_err(rt_err)
    }

    fn items(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let items = block(rb_self.0.items())?.map_err(rt_err)?;

        wrap_items(ruby, items)
    }

    /// Every item whose attributes contain the given pairs.
    fn search(ruby: &Ruby, rb_self: &Self, attributes: RHash) -> Result<RArray, Error> {
        let attributes = attributes_from(attributes)?;
        let items = block(rb_self.0.search_items(&attributes))?.map_err(rt_err)?;

        wrap_items(ruby, items)
    }

    /// Store a secret. `replace` overwrites any item with the same attributes,
    /// which is what makes a rotated token one item rather than a pile of them.
    fn create(
        &self,
        label: String,
        attributes: RHash,
        secret: String,
        replace: bool,
    ) -> Result<(), Error> {
        let attributes = attributes_from(attributes)?;

        block(self.0.create_item(&label, &attributes, CoreSecret::text(secret), replace))?
            .map_err(rt_err)
    }

    fn delete(&self, attributes: RHash) -> Result<(), Error> {
        let attributes = attributes_from(attributes)?;

        block(self.0.delete(&attributes))?.map_err(rt_err)
    }
}

fn wrap_items(ruby: &Ruby, items: Vec<CoreItem>) -> Result<RArray, Error> {
    let array = ruby.ary_new_capa(items.len());

    for item in items {
        array.push(Item(item))?;
    }

    Ok(array)
}

// --- Item ------------------------------------------------------------------

#[magnus::wrap(class = "Oo7::Item", free_immediately, size)]
struct Item(CoreItem);

impl Item {
    fn label(&self) -> Result<String, Error> {
        block(self.0.label())?.map_err(rt_err)
    }

    fn set_label(&self, label: String) -> Result<(), Error> {
        block(self.0.set_label(&label))?.map_err(rt_err)
    }

    fn attributes(ruby: &Ruby, rb_self: &Self) -> Result<RHash, Error> {
        let attributes = block(rb_self.0.attributes())?.map_err(rt_err)?;

        attributes_to(ruby, attributes)
    }

    fn set_attributes(&self, attributes: RHash) -> Result<(), Error> {
        let attributes = attributes_from(attributes)?;

        block(self.0.set_attributes(&attributes))?.map_err(rt_err)
    }

    /// The secret as a String. A blob that is not UTF-8 is an error rather than
    /// a mangled string, because a truncated passphrase opens nothing.
    fn secret(ruby: &Ruby, rb_self: &Self) -> Result<String, Error> {
        let secret = block(rb_self.0.secret())?.map_err(rt_err)?;

        String::from_utf8(secret.as_bytes().to_vec())
            .map_err(|_| Error::new(ruby.exception_arg_error(), "the secret is not valid UTF-8"))
    }

    fn set_secret(&self, secret: String) -> Result<(), Error> {
        block(self.0.set_secret(CoreSecret::text(secret)))?.map_err(rt_err)
    }

    fn is_locked(&self) -> Result<bool, Error> {
        block(self.0.is_locked())?.map_err(rt_err)
    }

    fn lock(&self) -> Result<(), Error> {
        block(self.0.lock())?.map_err(rt_err)
    }

    fn unlock(&self) -> Result<(), Error> {
        block(self.0.unlock())?.map_err(rt_err)
    }

    fn delete(&self) -> Result<(), Error> {
        block(self.0.delete())?.map_err(rt_err)
    }

    /// Seconds since the epoch, as the service reports them.
    fn created(&self) -> Result<u64, Error> {
        block(self.0.created())?.map(|d| d.as_secs()).map_err(rt_err)
    }

    fn modified(&self) -> Result<u64, Error> {
        block(self.0.modified())?.map(|d| d.as_secs()).map_err(rt_err)
    }
}

// --- init ------------------------------------------------------------------

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let namespace = ruby.define_module("Oo7")?;

    let keyring = namespace.define_class("Keyring", ruby.class_object())?;
    keyring.define_singleton_method("new", function!(Keyring::new, 0))?;
    keyring.define_method("unlock", method!(Keyring::unlock, 0))?;
    keyring.define_method("lock", method!(Keyring::lock, 0))?;
    keyring.define_method("locked?", method!(Keyring::is_locked, 0))?;
    keyring.define_method("items", method!(Keyring::items, 0))?;
    keyring.define_method("search", method!(Keyring::search, 1))?;
    keyring.define_method("create", method!(Keyring::create, 4))?;
    keyring.define_method("delete", method!(Keyring::delete, 1))?;

    let item = namespace.define_class("Item", ruby.class_object())?;
    item.define_method("label", method!(Item::label, 0))?;
    item.define_method("label=", method!(Item::set_label, 1))?;
    item.define_method("attributes", method!(Item::attributes, 0))?;
    item.define_method("attributes=", method!(Item::set_attributes, 1))?;
    item.define_method("secret", method!(Item::secret, 0))?;
    item.define_method("secret=", method!(Item::set_secret, 1))?;
    item.define_method("locked?", method!(Item::is_locked, 0))?;
    item.define_method("lock", method!(Item::lock, 0))?;
    item.define_method("unlock", method!(Item::unlock, 0))?;
    item.define_method("delete", method!(Item::delete, 0))?;
    item.define_method("created", method!(Item::created, 0))?;
    item.define_method("modified", method!(Item::modified, 0))?;

    Ok(())
}

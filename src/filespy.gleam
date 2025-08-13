//// This module is a wrapper around the erlang [FS](https://fs.n2o.dev/)
//// library. It allows you to create a listener for file change events for any
//// operating system.
////
//// Note: on Linux and BSD, you need `inotify-tools` installed.

import gleam/dynamic/decode
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

@external(erlang, "filespy_ffi", "identity")
fn coerce(value: a) -> b

/// Phantom type to indicate the Builder has no directories
pub type NoDirectories

/// Phantom type to indicate the Builder has directories
pub type HasDirectories

/// Phantom type to indicate the Builder has no handlers
pub type NoHandler

/// Phantom type to indicate the Builder has a handler
pub type HasHandler

/// Phantom type to indicate the Builder has no initial state
pub type NoInitialState

/// Phantom type to indicate the Builder has an initial state
pub type HasInitialState

/// Possible filesystem events
pub type Event {
  Created
  Modified
  Closed
  Deleted
  Renamed
  Attribute
  Unknown(Atom)
}

/// A filesystem change
pub type Change(custom) {
  Change(path: String, events: List(Event))
  Custom(custom)
}

/// Handler function called when an event is detected
pub type Handler =
  fn(String, Event) -> Nil

/// Handler function used with an actor handler
pub type ActorHandler(a, custom) =
  fn(a, Change(custom)) -> actor.Next(a, Change(custom))

/// Opaque builder type to instantiate the listener
///
/// Instantiate it with `new`.
pub opaque type Builder(a, d, h, s, custom) {
  Builder(
    dirs: List(String),
    handler: Option(ActorHandler(a, custom)),
    initializer: Option(
      fn(process.Subject(Change(custom))) ->
        Result(
          actor.Initialised(a, Change(custom), process.Subject(Change(custom))),
          String,
        ),
    ),
  )
}

/// Create a new builder
///
/// Use this with the `add_dir` and `handler` functions to configure the
/// watcher
pub fn new() -> Builder(a, NoDirectories, NoHandler, NoInitialState, Nil) {
  Builder(dirs: [], handler: None, initializer: None)
}

/// Add a directory to watch
///
/// # Examples
///
/// ```gleam
/// filespy.new()
/// |> filespy.add_dir("./watched")
/// ```
pub fn add_dir(
  builder: Builder(a, d, h, s, custom),
  directory: String,
) -> Builder(a, HasDirectories, h, s, custom) {
  Builder(initializer: builder.initializer, handler: builder.handler, dirs: [
    directory,
    ..builder.dirs
  ])
}

/// Add multiple directories at once
pub fn add_dirs(
  builder: Builder(a, d, h, s, custom),
  directories: List(String),
) -> Builder(a, HasDirectories, h, s, custom) {
  Builder(
    initializer: builder.initializer,
    handler: builder.handler,
    dirs: list.append(directories, builder.dirs),
  )
}

/// Set the handler
///
/// # Examples
///
/// ```gleam
/// filespy.new()
/// |> filespy.add_dir("./watched")
/// |> filespy.set_handler(fn (path: String, event: filespy.Event) {
///     case event {
///       filespy.Created -> {
///         io.println("File " <> path <> " created")
///       }
///       _ -> {
///         io.println("Something else happened to " <> path)
///       }
///   }
/// })
pub fn set_handler(
  builder: Builder(Nil, d, NoHandler, NoInitialState, custom),
  handler: Handler,
) -> Builder(Nil, d, HasHandler, HasInitialState, custom) {
  let wrapped_handler = fn(_state: Nil, event: Change(custom)) -> actor.Next(
    Nil,
    Change(custom),
  ) {
    case event {
      Change(path, events) -> {
        list.each(events, fn(ev) { handler(path, ev) })
      }
      _ -> Nil
    }
    actor.continue(Nil)
  }
  builder
  |> set_actor_handler(wrapped_handler)
  |> set_initial_state(Nil)
}

/// Set the actor handler
///
/// Use this if you want to have a more thorough control over the generated
/// actor. You will also need to set an initial state, with `set_initial_state`.
pub fn set_actor_handler(
  builder: Builder(a, d, NoHandler, s, custom),
  handler: ActorHandler(a, custom),
) -> Builder(a, d, HasHandler, s, custom) {
  Builder(
    initializer: builder.initializer,
    dirs: builder.dirs,
    handler: Some(handler),
  )
}

/// Set the initial state
///
/// Use this if you want to have a more thorough control over the generated
/// actor. You'll only have access to this state if you set your handler with
/// `set_actor_handler`.
pub fn set_initial_state(
  builder: Builder(a, d, h, NoInitialState, custom),
  state: a,
) -> Builder(a, d, h, HasInitialState, custom) {
  Builder(
    dirs: builder.dirs,
    handler: builder.handler,
    initializer: Some(fn(self: process.Subject(Change(custom))) -> Result(
      actor.Initialised(a, Change(custom), process.Subject(Change(custom))),
      String,
    ) {
      Ok(actor.initialised(state) |> actor.returning(self))
    }),
  )
}

/// Set the initializer
///
/// Use this if you want to, for example, return a subject in the state. The
/// initializer will run in the actor's `on_init`, so it'll run under the
/// watcher process
pub fn set_initializer(
  builder: Builder(a, d, h, NoInitialState, custom),
  initializer: fn(process.Subject(Change(custom))) ->
    Result(
      actor.Initialised(a, Change(custom), process.Subject(Change(custom))),
      String,
    ),
) -> Builder(a, d, h, HasInitialState, custom) {
  Builder(
    dirs: builder.dirs,
    handler: builder.handler,
    initializer: Some(initializer),
  )
}

@external(erlang, "fs", "start_link")
fn fs_start_link(name: Atom, path: String) -> Result(process.Pid, Nil)

@external(erlang, "fs", "subscribe")
fn fs_subscribe(name: Atom) -> Atom

/// Decode an atom to an `Event`.
fn event_decoder() -> decode.Decoder(Event) {
  use event <- decode.map(atom.decoder())
  let created = atom.create("created")
  let deleted = atom.create("deleted")
  let modified = atom.create("modified")
  let closed = atom.create("closed")
  let renamed = atom.create("renamed")
  let attrib = atom.create("attribute")
  let removed = atom.create("removed")
  case event {
    ev if ev == created -> Created
    ev if ev == deleted -> Deleted
    ev if ev == modified -> Modified
    ev if ev == closed -> Closed
    ev if ev == renamed -> Renamed
    ev if ev == removed -> Deleted
    ev if ev == attrib -> Attribute
    other -> Unknown(other)
  }
}

/// Decode a [`charlist`](https://hexdocs.pm/gleam_erlang/gleam/erlang/charlist.html#Charlist)
/// from a `Dynamic` value, and convert it to `String`.
fn charlist_decoder() -> decode.Decoder(String) {
  use chars <- decode.map(decode.dynamic)
  charlist.to_string(coerce(chars))
}

/// Decode `fs` events. Return type is `#(Pid, FileEvent, #(Path, List(Event)))`.
fn change_decoder() {
  use pid <- decode.field(0, decode.dynamic)
  use file_event <- decode.field(1, decode.dynamic)
  use all_events <- decode.field(2, {
    use path <- decode.field(0, charlist_decoder())
    use events <- decode.field(1, decode.list(of: event_decoder()))
    decode.success(#(path, events))
  })
  decode.success(#(pid, file_event, all_events))
}

/// Get a `Selector` which can be used to select for filesystem events.
pub fn selector() -> process.Selector(Change(custom)) {
  use event <- process.select_other(process.new_selector())
  case decode.run(event, change_decoder()) {
    Ok(#(_pid, _, #(path, events))) -> Change(path:, events:)
    _ -> Change(path: "", events: [])
  }
}

/// Start an actor which will receive filesystem events
///
/// In order for this to work, you'll need to have set some directories to be
/// watched, with `add_dir`, and set a handler with either `set_handler` or
/// `set_actor_handler` and `set_initial_state`
pub fn start(
  builder: Builder(a, HasDirectories, HasHandler, HasInitialState, custom),
) -> actor.StartResult(process.Subject(Change(custom))) {
  let assert Some(handler) = builder.handler
  let assert Some(initializer) = builder.initializer

  let composed_initializer = fn(self: process.Subject(Change(custom))) {
    let #(oks, errs) =
      builder.dirs
      |> list.map(fn(dir) {
        let watcher = atom.create("fs_watcher" <> dir)
        fs_start_link(watcher, dir)
        |> result.map(fn(pid) { #(pid, watcher) })
      })
      |> result.partition()

    case errs {
      [] -> {
        oks
        |> list.each(fn(res) {
          let #(_pid, watcher) = res
          fs_subscribe(watcher)
        })
        use a <- result.map(initializer(self))
        a |> actor.selecting(selector())
      }
      errs -> {
        list.each(oks, fn(res) {
          let #(pid, _watcher) = res
          process.kill(pid)
        })
        Error("Failed to start watcher: " <> string.inspect(errs))
      }
    }
  }

  actor.new_with_initialiser(5000, composed_initializer)
  |> actor.on_message(handler)
  |> actor.start()
}

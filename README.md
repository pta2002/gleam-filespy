# filespy

[![Package Version](https://img.shields.io/hexpm/v/filespy)](https://hex.pm/packages/filespy)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/filespy/)

Filespy is a small library and versatile library that allows you to watch for filesystem events from Gleam! It's a type-safe wrapper around the erlang [FS](https://github.com/5HT/fs) library.

## Quick start

Add the library to your requirements with `gleam add`:

```sh
gleam add filespy
```

**Note**: If you use Linux or a BSD, you need to install `inotify-tools`!

## Usage

The library is configured via a simple builder:

```gleam
import filespy
import gleam/io
import gleam/erlang/process

fn main() {
    let _res = filespy.new()   // Create the builder
    |> filespy.add_dir(".")    // Watch the current directory
    |> filespy.add_dir("/mnt") // Watch the /mnt directory
    |> filespy.set_handler(fn (path, event) {
        // This callback will be run every time a filesystem event is detected
        // in the specified directories
        io.debug(#(path, event))
        Nil
    })
    |> filespy.start()        // Start the watcher!

    process.sleep_forever()
}
```

If you want to, you can also go lower level, and configure the underlying actor:

```gleam
import filespy
import gleam/io

fn main() {
    let _res = filespy.new()        // Create the builder
    |> filespy.add_dir(".")         // Watch the current directory
    |> filespy.add_dir("/mnt")      // Watch the /mnt directory
    |> filespy.set_initial_state(0) // Initial state for the actor, this is required!
    |> filespy.set_actor_handler(fn (message, state) {
        // This callback will be run every time a filesystem event is detected
        // in the specified directories

        // In the actor handler, multiple events might be sent at once.
        let filespy.Change(path: path, events: events) = message
        io.debug(#(path, events, state))
        
        actor.continue(state + 1)
    })
    |> filespy.start()              // Start the watcher!

    process.sleep_forever()
}
```

You can go even lower level, and get the actor start spec to configure it yourself:

```gleam
import filespy
import gleam/io

fn main() {
    let start_spec = filespy.new()  // Create the builder
    |> filespy.add_dir(".")         // Watch the current directory
    |> filespy.add_dir("/mnt")      // Watch the /mnt directory
    |> filespy.set_initial_state(0) // Initial state for the actor, this is required!
    |> filespy.set_actor_handler(fn (message, state) {
        // This callback will be run every time a filesystem event is detected
        // in the specified directories

        // In the actor handler, multiple events might be sent at once.
        let filespy.Change(path: path, events: events) = message
        io.debug(#(path, events, state))
        
        actor.continue(state + 1)
    })
    |> filespy.spec()               // Get the spec

    actor.start_spec(start_spec)

    process.sleep_forever()
}
```

## Documentation
If you have any more questions, check out the [documentation](https://hexdocs.pm/filespy)!

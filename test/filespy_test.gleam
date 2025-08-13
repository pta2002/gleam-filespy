import filespy
import gleam/erlang/atom
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

/// Create a file, and try to read the events. Because file is created in /tmp,
/// some few events can be triggered from different paths, notably xattrmod or
/// deleted/removed.
pub fn file_creation_test() {
  use <- filespy_setup()
  use path, event <- start_filespy()
  let xattrmod = atom.create("xattrmod")
  let xattrmod = filespy.Unknown(xattrmod)
  [filespy.Created, xattrmod, filespy.Deleted, filespy.Modified]
  |> list.contains(event)
  |> should.be_true
  path
  |> string.contains("filespy")
  |> should.be_true
}

fn filespy_setup(next: fn() -> process.Subject(filespy.Change(a))) -> Nil {
  // Create the temporary directory to get events from, launch the
  // filespy process & create file to trigger some fsevents events.
  simplifile.create_directory_all("/tmp/filespy") |> should.be_ok
  let filespy_process = next()
  let _ = simplifile.create_file("/tmp/filespy/example.txt")

  // Because fsevents is an async process, sleeping is required to make sure
  // every events are correctly handled in the filespy handler.
  process.sleep(1000)

  // Terminate the filespy process & clean the temporary folder.
  let assert Ok(owner) = process.subject_owner(filespy_process)
  process.send_exit(owner)
  simplifile.delete("/tmp/filespy") |> should.be_ok
}

fn start_filespy(
  handler: fn(String, filespy.Event) -> Nil,
) -> process.Subject(filespy.Change(Nil)) {
  let filespy_actor =
    filespy.new()
    |> filespy.add_dir("/tmp/filespy")
    |> filespy.set_handler(handler)
    |> filespy.start()
    |> should.be_ok
  filespy_actor.data
}

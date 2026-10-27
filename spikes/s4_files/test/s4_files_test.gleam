import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleeunit
import polly
import simplifile
import store

pub fn main() -> Nil {
  gleeunit.main()
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic(unit: Unit) -> Int

@external(erlang, "os", "system_time")
fn system_time(unit: Unit) -> Int

type Unit {
  Millisecond
}

fn now() -> Int {
  monotonic(Millisecond)
}

fn temp_dir(name: String) -> String {
  let dir = "/tmp/zeno-s4/" <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

/// Sleep until `offset` ms past the next whole second.
fn align_to_second(offset: Int) -> Nil {
  let ms = system_time(Millisecond) % 1000
  process.sleep(1000 - ms + offset)
}

fn report(label: String, latencies: List(Int)) -> Nil {
  let max = list.fold(latencies, 0, int.max)
  let mean = int.sum(latencies) / int.max(list.length(latencies), 1)
  io.println(
    "\n"
    <> label
    <> ": n="
    <> int.to_string(list.length(latencies))
    <> " mean="
    <> int.to_string(mean)
    <> "ms max="
    <> int.to_string(max)
    <> "ms",
  )
}

/// External writes one per second from another process: polly sees each
/// within 300 ms.
pub fn polly_latency_test() {
  let dir = temp_dir("polly")
  let path = dir <> "/deck.md"
  let assert Ok(_) = simplifile.write(path, "start")
  let events = process.new_subject()
  let assert Ok(watcher) =
    polly.new()
    |> polly.add_file(path)
    |> polly.interval(250)
    |> polly.add_subject(events)
    |> polly.watch
  let latencies =
    list.map(range(1, 20), fn(i) {
      align_to_second(100)
      let start = now()
      process.spawn(fn() {
        let _ = simplifile.write(path, "edit " <> int.to_string(i))
      })
      let assert Ok(polly.Changed(_)) = process.receive(events, 1000)
      now() - start
    })
  polly.stop(watcher)
  report("polly latency", latencies)
  assert list.all(latencies, fn(l) { l < 300 })
}

/// Two external writes within one second: polly misses the second, because
/// it compares mtime in whole seconds.
pub fn polly_same_second_test() {
  let dir = temp_dir("polly2")
  let path = dir <> "/deck.md"
  let assert Ok(_) = simplifile.write(path, "start")
  let events = process.new_subject()
  let assert Ok(watcher) =
    polly.new()
    |> polly.add_file(path)
    |> polly.interval(250)
    |> polly.add_subject(events)
    |> polly.watch
  let missed =
    list.count(range(1, 5), fn(i) {
      align_to_second(50)
      let _ = simplifile.write(path, "first " <> int.to_string(i))
      let assert Ok(_) = process.receive(events, 600)
      let _ = simplifile.write(path, "second " <> int.to_string(i))
      process.receive(events, 1500) |> is_error
    })
  polly.stop(watcher)
  io.println(
    "\npolly same-second writes missed: " <> int.to_string(missed) <> "/5",
  )
  assert missed > 0
}

fn is_error(r: Result(a, b)) -> Bool {
  case r {
    Ok(_) -> False
    Error(_) -> True
  }
}

/// The content poller sees every external write, including two in the same
/// second, within 300 ms.
pub fn content_poll_test() {
  let dir = temp_dir("poll")
  let path = dir <> "/deck.md"
  let assert Ok(_) = simplifile.write(path, "start")
  let events = process.new_subject()
  let stop = store.poll(path, 250, events)
  let latencies =
    list.map(range(1, 20), fn(i) {
      process.sleep(300 + i * 7)
      let start = now()
      process.spawn(fn() {
        let _ = simplifile.write(path, "edit " <> int.to_string(i))
      })
      let assert Ok(_) = process.receive(events, 1000)
      now() - start
    })
  process.send(stop, Nil)
  report("content poll latency", latencies)
  assert list.all(latencies, fn(l) { l < 300 })
}

/// Own writes are recognised by hash and ignored; external writes are not.
pub fn own_writes_test() {
  let dir = temp_dir("own")
  let path = dir <> "/deck.md"
  let assert Ok(_) = store.write_atomic(path, <<"start">>)
  let events = process.new_subject()
  let stop = store.poll(path, 250, events)
  let #(own, external) =
    list.fold(range(1, 10), #([], []), fn(acc, i) {
      let #(own, external) = acc
      let bytes = <<"own ":utf8, int.to_string(i):utf8>>
      let assert Ok(_) = store.write_atomic(path, bytes)
      process.sleep(400)
      let text = "external " <> int.to_string(i)
      let assert Ok(_) = simplifile.write(path, text)
      process.sleep(400)
      #([store.hash(bytes), ..own], [store.hash(<<text:utf8>>), ..external])
    })
  process.sleep(300)
  process.send(stop, Nil)
  let seen = drain(events, [])
  let ignored = list.count(seen, list.contains(own, _))
  let reported = list.filter(seen, fn(h) { !list.contains(own, h) })
  io.println(
    "\nown writes ignored: "
    <> int.to_string(ignored)
    <> "/10, external seen: "
    <> int.to_string(list.length(reported))
    <> "/10",
  )
  assert ignored == 10
  assert list.sort(reported, string.compare)
    == list.sort(external, string.compare)
}

fn drain(events, acc: List(String)) -> List(String) {
  case process.receive(events, 0) {
    Ok(h) -> drain(events, [h, ..acc])
    Error(_) -> list.reverse(acc)
  }
}

/// A reader racing 500 writes of two 1 MB contents. Atomic writes are
/// always seen whole; plain writes are the control and show torn reads.
pub fn atomic_write_test() {
  let atomic = torn_reads(fn(path, bytes) { store.write_atomic(path, bytes) })
  let plain =
    torn_reads(fn(path, bytes) {
      case simplifile.write_bits(path, bytes) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    })
  io.println(
    "\ntorn reads: atomic "
    <> int.to_string(atomic.0)
    <> " of "
    <> int.to_string(atomic.1)
    <> ", plain "
    <> int.to_string(plain.0)
    <> " of "
    <> int.to_string(plain.1),
  )
  assert atomic.0 == 0
  assert plain.0 > 0
}

fn torn_reads(write: fn(String, BitArray) -> Result(Nil, Nil)) -> #(Int, Int) {
  let dir = temp_dir("atomic")
  let path = dir <> "/deck.md"
  let a = big("a")
  let b = big("b")
  let good = [store.hash(a), store.hash(b)]
  let assert Ok(_) = write(path, a)
  let ready = process.new_subject()
  let result = process.new_subject()
  process.spawn(fn() {
    let done = process.new_subject()
    process.send(ready, done)
    process.send(result, read_loop(path, good, done, 0, 0))
  })
  let assert Ok(done) = process.receive(ready, 1000)
  list.each(range(1, 500), fn(i) {
    let assert Ok(_) =
      write(path, case i % 2 {
        0 -> a
        _ -> b
      })
  })
  process.send(done, Nil)
  let assert Ok(counts) = process.receive(result, 5000)
  counts
}

fn read_loop(path, good, done, torn: Int, total: Int) -> #(Int, Int) {
  case process.receive(done, 0) {
    Ok(Nil) -> #(torn, total)
    Error(Nil) -> {
      let ok = list.contains(good, store.read_hash(path))
      read_loop(
        path,
        good,
        done,
        case ok {
          True -> torn
          False -> torn + 1
        },
        total + 1,
      )
    }
  }
}

fn big(letter: String) -> BitArray {
  <<string.repeat(letter, 1_048_576):utf8>>
}

fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}

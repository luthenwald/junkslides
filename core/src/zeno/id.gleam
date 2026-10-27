//// Cell and slide IDs. This is the only module that sees an ID as a string.
////
//// IDs are RFC 9562 UUIDs. Fresh ones are version 7 and come from an
//// `IdSupply`, a pure value: the caller seeds it with the current time in
//// milliseconds and some random bits, and the supply counts upwards from
//// there (RFC 9562, section 6.2, method 1: a 12-bit counter in `rand_a`).

import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/order.{type Order}
import gleam/set.{type Set}
import gleam/string

pub type CellTag

pub type SlideTag

/// Opaque: only this module can create or parse an Id. The phantom tag keeps
/// cell IDs and slide IDs apart.
pub opaque type Id(tag) {
  Id(uuid: String)
}

/// A source of fresh IDs, passed in so the core stays pure.
pub opaque type IdSupply {
  IdSupply(ms: Int, counter: Int, entropy: BitArray)
}

const counter_limit = 4096

/// A supply seeded with Unix time in milliseconds and random bits. Only the
/// first 62 bits of `entropy` are used; missing bits are zero.
pub fn supply(ms: Int, entropy: BitArray) -> IdSupply {
  let size = bit_array.bit_size(entropy)
  let entropy = case entropy {
    <<bits:bits-size(62), _:bits>> -> bits
    _ -> <<entropy:bits, 0:size({ 62 - size })>>
  }
  IdSupply(ms:, counter: 0, entropy:)
}

/// A deterministic supply for tests. Different seeds give disjoint IDs.
pub fn test_supply(seed: Int) -> IdSupply {
  supply(seed * counter_limit, <<>>)
}

/// The next ID that is not in `taken`.
pub fn fresh(supply: IdSupply, taken: IdSet) -> #(Id(tag), IdSupply) {
  let IdSupply(ms:, counter:, entropy:) = supply
  let assert <<bits:bits-size(62)>> = entropy
  let bytes = <<ms:size(48), 7:size(4), counter:size(12), 2:size(2), bits:bits>>
  let id = Id(format(bytes))
  let next = case counter + 1 == counter_limit {
    True -> IdSupply(ms: ms + 1, counter: 0, entropy:)
    False -> IdSupply(ms:, counter: counter + 1, entropy:)
  }
  case contains(taken, id) {
    True -> fresh(next, taken)
    False -> #(id, next)
  }
}

/// A set of IDs of either kind. Deck invariant 2 asks for distinct IDs
/// across cells and slides, so membership ignores the tag.
pub opaque type IdSet {
  IdSet(uuids: Set(String))
}

pub fn empty_set() -> IdSet {
  IdSet(set.new())
}

pub fn insert(ids: IdSet, id: Id(tag)) -> IdSet {
  IdSet(set.insert(ids.uuids, id.uuid))
}

pub fn contains(ids: IdSet, id: Id(tag)) -> Bool {
  set.contains(ids.uuids, id.uuid)
}

pub fn union(a: IdSet, b: IdSet) -> IdSet {
  IdSet(set.union(a.uuids, b.uuids))
}

pub fn size(ids: IdSet) -> Int {
  set.size(ids.uuids)
}

fn format(bytes: BitArray) -> String {
  let hex = bit_array.base16_encode(bytes) |> string.lowercase
  string.slice(hex, 0, 8)
  <> "-"
  <> string.slice(hex, 8, 4)
  <> "-"
  <> string.slice(hex, 12, 4)
  <> "-"
  <> string.slice(hex, 16, 4)
  <> "-"
  <> string.slice(hex, 20, 12)
}

/// Accepts a lowercase UUID of any RFC 9562 version (1 to 8) in the
/// 36-character form.
pub fn parse(text: String) -> Result(Id(tag), Nil) {
  let graphemes = string.to_graphemes(text)
  let valid =
    list.length(graphemes) == 36
    && list.index_fold(graphemes, True, fn(ok, g, i) {
      ok
      && case i {
        8 | 13 | 18 | 23 -> g == "-"
        14 -> string.contains("12345678", g)
        19 -> string.contains("89ab", g)
        _ -> string.contains("0123456789abcdef", g)
      }
    })
  case valid {
    True -> Ok(Id(text))
    False -> Error(Nil)
  }
}

pub fn to_string(id: Id(tag)) -> String {
  id.uuid
}

/// True for the same UUID, whatever the tags. Deck invariant 2 asks for
/// distinct IDs across cells and slides.
pub fn same(a: Id(a), b: Id(b)) -> Bool {
  a.uuid == b.uuid
}

pub fn compare(a: Id(tag), b: Id(tag)) -> Order {
  string.compare(a.uuid, b.uuid)
}

pub fn to_json(id: Id(tag)) -> Json {
  json.string(id.uuid)
}

pub fn decoder() -> Decoder(Id(tag)) {
  use text <- decode.then(decode.string)
  case parse(text) {
    Ok(id) -> decode.success(id)
    Error(Nil) -> decode.failure(Id(""), "Id")
  }
}

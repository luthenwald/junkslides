import junkslides/id.{type CellTag, type Id}

pub fn fresh_ids_are_v7_and_parse_test() {
  let supply =
    id.supply(0x019a2c417f10, <<255, 255, 255, 255, 255, 255, 255, 255>>)
  let #(first, supply): #(Id(CellTag), _) = id.fresh(supply, id.empty_set())
  let #(second, _): #(Id(CellTag), _) = id.fresh(supply, id.empty_set())
  assert id.to_string(first) == "019a2c41-7f10-7000-bfff-ffffffffffff"
  assert id.to_string(second) == "019a2c41-7f10-7001-bfff-ffffffffffff"
  assert id.parse(id.to_string(first)) == Ok(first)
}

pub fn fresh_skips_taken_ids_test() {
  let supply = id.test_supply(1)
  let #(first, _): #(Id(CellTag), _) = id.fresh(supply, id.empty_set())
  let #(second, _): #(Id(CellTag), _) =
    id.fresh(supply, id.insert(id.empty_set(), first))
  assert first != second
}

pub fn counter_rolls_over_into_the_timestamp_test() {
  let supply = id.supply(5, <<>>)
  let #(_, last): #(Id(CellTag), _) = take(supply, 4096)
  let #(next, _): #(Id(CellTag), _) = id.fresh(last, id.empty_set())
  assert id.to_string(next) == "00000000-0006-7000-8000-000000000000"
}

fn take(supply, n) {
  let #(new, supply) = id.fresh(supply, id.empty_set())
  case n {
    1 -> #(new, supply)
    _ -> take(supply, n - 1)
  }
}

pub fn parse_test() {
  let parse = fn(text) -> Result(Id(CellTag), Nil) { id.parse(text) }
  assert parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02") != Error(Nil)
  // Any version 1 to 8 is accepted.
  assert parse("019a2c41-7f10-4b2e-9c4d-1a2b3c4d5e02") != Error(Nil)
  // Uppercase, wrong variant, wrong version, wrong length, wrong hyphens.
  assert parse("019A2C41-7F10-7B2E-9C4D-1A2B3C4D5E02") == Error(Nil)
  assert parse("019a2c41-7f10-7b2e-cc4d-1a2b3c4d5e02") == Error(Nil)
  assert parse("019a2c41-7f10-0b2e-9c4d-1a2b3c4d5e02") == Error(Nil)
  assert parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e0") == Error(Nil)
  assert parse("019a2c417f10-7b2e-9c4d-1a2b3c4d5e02-") == Error(Nil)
  // Too long, version 9, and a character outside ASCII in place of one.
  assert parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e021") == Error(Nil)
  assert parse("019a2c41-7f10-9b2e-9c4d-1a2b3c4d5e02") == Error(Nil)
  assert parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5eé") == Error(Nil)
  assert parse("") == Error(Nil)
}

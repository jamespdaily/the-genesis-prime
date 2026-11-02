//// Every kind of field a message body holds, written and read back by the bit
//// stream, for values drawn at random: the kinds are the ones the schema
//// lists (dev/genesis_prime/message_schema.gleam, `Kind`), each written after
//// 0 to 7 other bits so it starts at every offset in a byte. Expected values
//// are the properties of the client's bit stream.
//// - A value reads back as written, and the body ends where the last field
////   did (ReadBits32 0x14006c090, WriteBits 0x140336380; a body is padded with
////   zero bits to a whole byte, WriteMessageFrame 0x1403355e0).
//// - A body cut by its last byte ends inside a field and is refused
////   (0x80070026, ReadBitsSlow 0x140336d60).
//// - A value that does not fit its width, or sits at or above the limit the
////   schema sets, is refused when written and when read; a fixed value reads
////   back only as itself.
//// - A float32 keeps its bits, so every pattern of 32 bits round-trips
////   (ReadFloat 0x14006c1c0).
//// - A wide text counts its UTF-16 units in 7 bits, or in 15 when it has more
////   than 127 (WriteWideText 0x140336040), a counted text in 16 bits with a
////   zero after the units (WriteCountedWideText 0x1400c2f70).
//// - A list whose items start with a kind that picks their layout, as the
////   movement commands of message 0x637 do (0x140c1f070, 0x1400af930): the
////   kind is read without moving on, so the layout's reader takes it as its
////   first field, a kind with no layout fails the read, and a count that
////   promises more items than the bytes hold fails where the bytes end
////   (0x1400b06f0).
//// - A list of records counted by an earlier list holds as many items as that
////   list, with no count of its own (0x140c1f070: kinds 3, 9, 12 and 15 hold
////   n vectors after n values).

import genesis_prime/message/bit_stream.{type DecodeError, type Reader}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import owned_test
import qcheck.{type Generator}

/// One field of a body, with the width, count or limit the schema gives it.
type Field {
  Unsigned(bits: Int, value: Int)
  UnsignedBelow(bits: Int, limit: Int, value: Int)
  Float32(bits: Int)
  WideText(text: String)
  CountedWideText(max_units: Int, text: String)
  Guid(bytes: BitArray)
  Endpoint(endpoint: bit_stream.Endpoint)
  RawBytes(bytes: BitArray)
  WholeFrame(frame: BitArray)
  WideTexts(count_bits: Int, texts: List(String))
  UnsignedArray(count_bits: Int, bits: Int, items: List(Int))
  Float32Array(count_bits: Int, items: List(Int))
  UnsignedArrayLike(bits: Int, items: List(Int))
  Constant(bits: Int, value: Int)
  Records(count_bits: Int, items: List(Item))
  RecordsLike(like: List(Int), items: List(Item))
  Shapes(count_bits: Int, items: List(Shape))
}

/// The record inside an array, as the schema's records are: an unsigned value
/// and a wide text.
type Item {
  Item(number: Int, name: String)
}

/// An item of a list that picks its layout by its first 5 bits, as the
/// movement commands do: each layout starts with its own kind as a fixed value.
type Shape {
  /// Kind 3: one bit.
  Switch(Int)
  /// Kind 17: 32 bits, then 3 bits.
  Pair(#(Int, Int))
  /// Kind 30: a count of 4 bits, then that many values of 7 bits.
  Run(List(Int))
}

const shape_kind_bits = 5

// ---- the field kinds, one test each ----

pub fn an_unsigned_value_of_any_width_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(unsigned_field())
}

pub fn an_unsigned_value_below_a_limit_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(unsigned_below_field())
}

pub fn a_float32_keeps_every_pattern_of_its_32_bits_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(float32_field())
}

pub fn a_wide_text_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(wide_text_field())
}

pub fn a_counted_wide_text_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(counted_wide_text_field())
}

pub fn a_guid_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(guid_field())
}

pub fn an_endpoint_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(endpoint_field())
}

pub fn raw_bytes_read_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(raw_bytes_field())
}

pub fn a_whole_inner_frame_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(whole_frame_field())
}

pub fn an_array_of_wide_texts_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(wide_texts_field())
}

pub fn an_array_of_unsigned_values_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(unsigned_array_field())
}

pub fn an_array_of_float32_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(float32_array_field())
}

pub fn unsigned_values_counted_by_another_array_read_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(unsigned_array_like_field())
}

pub fn a_constant_reads_back_as_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(constant_field())
}

pub fn an_array_of_records_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(records_field())
}

pub fn an_array_of_tagged_items_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(shapes_field())
}

pub fn records_counted_by_another_array_read_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  reads_back(records_like_field())
}

pub fn a_peeked_value_is_the_next_read_and_moves_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(prefix_bits, prefix, bits, value) <- qcheck.given({
    use prefix_bits <- qcheck.bind(qcheck.bounded_int(from: 1, to: 7))
    use prefix <- qcheck.bind(unsigned_of(prefix_bits))
    use bits <- qcheck.bind(width())
    use value <- qcheck.map(unsigned_of(bits))
    #(prefix_bits, prefix, bits, value)
  })
  let assert Ok(bytes) =
    written(fn(writer) {
      writer
      |> bit_stream.write_unsigned("prefix", prefix, prefix_bits)
      |> bit_stream.write_unsigned("value", value, bits)
    })
    as "both values are within their widths"
  let reader = bit_stream.new_reader(bytes)
  let assert Ok(#(_, reader)) = bit_stream.read_unsigned(reader, prefix_bits)
    as "the bits before the value are there"
  assert bit_stream.peek_unsigned(reader, bits) == Ok(value)
    as "the peeked value is the one written"
  assert bit_stream.peek_unsigned(reader, bits) == Ok(value)
    as "peeking again gives the same value, so the reader did not move"
  let assert Ok(#(read, reader)) = bit_stream.read_unsigned(reader, bits)
    as "the value is there to read"
  assert read == value as "the next read is the peeked value"
  assert bit_stream.finish_reading(reader) == Ok(Nil)
    as "the value ended within the last byte"
}

pub fn a_peek_past_the_end_of_the_bytes_fails_like_a_read_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(bytes, extra) <- qcheck.given(qcheck.tuple2(
    qcheck.bounded_int(from: 0, to: 7),
    qcheck.bounded_int(from: 1, to: 8),
  ))
  let body = <<0:size({ bytes * 8 })>>
  assert bit_stream.peek_unsigned(
      bit_stream.new_reader(body),
      bytes * 8 + extra,
    )
    == Error(bit_stream.EndOfData)
    as "ReadBitsSlow 0x140336d60: a value that needs more bits than the bytes hold fails"
}

pub fn a_run_of_fields_of_every_kind_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  use fields <- qcheck.given(qcheck.generic_list(
    any_field(),
    qcheck.bounded_int(from: 0, to: 12),
  ))
  let written = list.fold(fields, bit_stream.new_writer(), write)
  let assert Ok(bytes) = bit_stream.finish(written)
    as "every field is within its width, so the run is written"
  let read =
    list.try_fold(fields, bit_stream.new_reader(bytes), fn(reader, field) {
      use #(read, reader) <- result.try(read(reader, like: field))
      assert read == field as "a field reads back as written"
      Ok(reader)
    })
  let assert Ok(reader) = read as "every written field is there to read"
  assert bit_stream.finish_reading(reader) == Ok(Nil)
    as "the last field ends within the last byte, so nothing whole is left"
}

// ---- refusals ----

pub fn an_unsigned_value_that_needs_more_than_its_width_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(bits, extra) <- qcheck.given(qcheck.tuple2(
    width(),
    qcheck.bounded_int(from: 0, to: 1000),
  ))
  let too_big = int.bitwise_shift_left(1, bits) + extra
  assert written(bit_stream.write_unsigned(_, "value", too_big, bits))
    == Error(bit_stream.ValueDoesNotFit(field: "value", bits:, value: too_big))
    as "a value of 2^bits or more does not fit"
  assert written(bit_stream.write_unsigned(_, "value", -1 - extra, bits))
    == Error(bit_stream.ValueDoesNotFit(
      field: "value",
      bits:,
      value: -1 - extra,
    ))
    as "a negative value does not fit"
}

pub fn a_value_at_or_above_the_limit_is_refused_when_written_and_when_read_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(bits, limit, over) <- qcheck.given({
    use bits <- qcheck.bind(qcheck.bounded_int(from: 2, to: 32))
    use limit <- qcheck.bind(qcheck.bounded_int(
      from: 1,
      to: int.bitwise_shift_left(1, bits) - 1,
    ))
    use over <- qcheck.map(qcheck.bounded_int(
      from: limit,
      to: int.bitwise_shift_left(1, bits) - 1,
    ))
    #(bits, limit, over)
  })
  assert written(bit_stream.write_unsigned_below(_, "value", over, bits, limit))
    == Error(bit_stream.ValueAtOrAboveLimit(field: "value", limit:, value: over))
    as "the encoder refuses a value at or above the limit"
  let assert Ok(body) =
    written(bit_stream.write_unsigned(_, "value", over, bits))
    as "the value fits the width"
  assert bit_stream.read_unsigned_below(
      bit_stream.new_reader(body),
      "value",
      bits,
      limit,
    )
    == Error(bit_stream.UnexpectedValue(field: "value", value: over))
    as "the decoder refuses a value at or above the limit"
}

pub fn a_constant_field_refuses_any_other_value_when_read_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(bits, value, other) <- qcheck.given({
    use bits <- qcheck.bind(qcheck.bounded_int(from: 1, to: 32))
    use value <- qcheck.bind(unsigned_of(bits))
    use change <- qcheck.map(qcheck.bounded_int(
      from: 1,
      to: int.bitwise_shift_left(1, bits) - 1,
    ))
    #(bits, value, int.bitwise_exclusive_or(value, change))
  })
  let assert Ok(body) =
    written(bit_stream.write_constant(_, "value", other, bits))
    as "the other value fits the width"
  assert bit_stream.read_constant(
      bit_stream.new_reader(body),
      "value",
      bits,
      value,
    )
    == Error(bit_stream.UnexpectedValue(field: "value", value: other))
    as "a value other than the fixed one is refused"
}

pub fn records_counted_by_an_array_of_another_length_are_refused_when_written_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(like, items) <- qcheck.given({
    use like <- qcheck.bind(qcheck.generic_list(
      unsigned_of(32),
      qcheck.bounded_int(from: 0, to: 6),
    ))
    use items <- qcheck.map(qcheck.generic_list(
      item_of(),
      qcheck.bounded_int(from: 0, to: 6),
    ))
    #(like, items)
  })
  use <- bool.guard(when: list.length(like) == list.length(items), return: Nil)
  assert written(bit_stream.write_array_like(_, "f", items, like, write_item))
    == Error(bit_stream.ItemCountDisagrees(
      field: "f",
      expected: list.length(like),
      actual: list.length(items),
    ))
    as "0x140c1f070: a command holds as many vectors as values, so a list of another length is not a command the client's reader takes"
}

pub fn a_count_that_promises_more_tagged_items_than_the_bytes_hold_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(more, shapes) <- qcheck.given(qcheck.tuple2(
    qcheck.bounded_int(from: 1, to: 4_000_000_000),
    qcheck.generic_list(shape_of(), qcheck.bounded_int(from: 0, to: 6)),
  ))
  let assert Ok(items) =
    written(fn(writer) { list.fold(shapes, writer, write_shape) })
    as "every shape is within its width"
  let counted = <<{ list.length(shapes) + more }:size(32)-little, items:bits>>
  let read =
    bit_stream.read_array(bit_stream.new_reader(counted), 32, read_shape)
  let assert Error(error) = result.replace(read, Nil)
    as "0x1400b06f0: the reader takes the commands one by one and fails where the bytes end, so a count of billions builds nothing"
  assert error == bit_stream.EndOfData
    || error == bit_stream.UnexpectedValue(field: "kind", value: 0)
    as "the read fails at the end of the bytes, or one item sooner when the zero bits that pad the last byte read as a kind 0, which this union has no layout for"
}

pub fn a_counted_text_of_exactly_its_limit_is_written_and_one_unit_more_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  use max_units <- qcheck.given(qcheck.bounded_int(from: 1, to: 250))
  let at_limit = string.repeat("x", max_units)
  let assert Ok(body) =
    written(bit_stream.write_counted_wide_text(_, "text", at_limit, max_units))
    as "a text of max_units units is within its limit"
  let read =
    bit_stream.read_counted_wide_text(bit_stream.new_reader(body), max_units)
  assert result.map(read, fn(found) { found.0 }) == Ok(at_limit)
    as "the text at its limit reads back"
  assert written(bit_stream.write_counted_wide_text(
      _,
      "text",
      string.repeat("x", max_units + 1),
      max_units,
    ))
    == Error(bit_stream.TextTooLong(
      field: "text",
      units: max_units + 1,
      limit: max_units,
    ))
    as "a text of one unit more is refused"
}

// ---- reading and writing a field ----

/// The bytes a body is when `write` writes into a new writer, or the first
/// error.
fn written(
  write: fn(bit_stream.Writer) -> bit_stream.Writer,
) -> Result(BitArray, bit_stream.EncodeError) {
  bit_stream.finish(write(bit_stream.new_writer()))
}

/// The property of every kind: after 0 to 7 bits of another field, `field`
/// reads back as written, the body ends where it did, and the body cut by its
/// last byte ends inside a field.
fn reads_back(kind: Generator(Field)) -> Nil {
  use #(prefix_bits, prefix, field) <- qcheck.given({
    use prefix_bits <- qcheck.bind(qcheck.bounded_int(from: 0, to: 7))
    use prefix <- qcheck.bind(unsigned_of(prefix_bits))
    use field <- qcheck.map(kind)
    #(prefix_bits, prefix, field)
  })
  let writer = case prefix_bits {
    0 -> bit_stream.new_writer()
    bits ->
      bit_stream.write_unsigned(bit_stream.new_writer(), "prefix", prefix, bits)
  }
  let assert Ok(bytes) = bit_stream.finish(write(writer, field))
    as "every field is within its width, so the field is written"
  let reads = fn(body: BitArray) -> Result(#(Field, Reader), DecodeError) {
    let reader = bit_stream.new_reader(body)
    use reader <- result.try(case prefix_bits {
      0 -> Ok(reader)
      bits -> {
        use #(read, reader) <- result.try(bit_stream.read_unsigned(reader, bits))
        assert read == prefix as "the bits before the field read back"
        Ok(reader)
      }
    })
    read(reader, like: field)
  }
  let assert Ok(#(read, reader)) = reads(bytes)
    as "the written field is there to read"
  assert read == field as "the field reads back as written"
  assert bit_stream.finish_reading(reader) == Ok(Nil)
    as "the field ends within the last byte, so nothing whole is left"
  // An empty list counted by nothing and without a prefix writes no bits, so
  // there is no last byte to cut.
  use <- bool.guard(when: bytes == <<>>, return: Nil)
  let cut_size = bit_array.byte_size(bytes) - 1
  let assert Ok(cut) = bit_array.slice(bytes, 0, cut_size)
    as "the body holds at least one byte"
  assert result.replace(reads(cut), Nil) == Error(bit_stream.EndOfData)
    as "a body without its last byte ends inside the field"
}

fn write(writer: bit_stream.Writer, field: Field) -> bit_stream.Writer {
  case field {
    Unsigned(bits:, value:) ->
      bit_stream.write_unsigned(writer, "f", value, bits)
    UnsignedBelow(bits:, limit:, value:) ->
      bit_stream.write_unsigned_below(writer, "f", value, bits, limit)
    Float32(bits:) -> bit_stream.write_float32_bits(writer, "f", bits)
    WideText(text:) -> bit_stream.write_wide_text(writer, "f", text)
    CountedWideText(max_units:, text:) ->
      bit_stream.write_counted_wide_text(writer, "f", text, max_units)
    Guid(bytes:) -> bit_stream.write_guid(writer, "f", bytes)
    Endpoint(endpoint:) -> bit_stream.write_endpoint(writer, "f", endpoint)
    RawBytes(bytes:) ->
      bit_stream.write_raw_bytes(writer, "f", bytes, bit_array.byte_size(bytes))
    WholeFrame(frame:) -> bit_stream.write_whole_frame(writer, "f", frame)
    WideTexts(count_bits:, texts:) ->
      bit_stream.write_wide_texts(writer, "f", texts, count_bits)
    UnsignedArray(count_bits:, bits:, items:) ->
      bit_stream.write_unsigned_array(writer, "f", items, count_bits, bits)
    Float32Array(count_bits:, items:) ->
      bit_stream.write_float32_array(writer, "f", items, count_bits)
    UnsignedArrayLike(bits:, items:) ->
      bit_stream.write_unsigned_array_like(writer, "f", items, items, bits)
    Constant(bits:, value:) ->
      bit_stream.write_constant(writer, "f", value, bits)
    Records(count_bits:, items:) ->
      bit_stream.write_array(writer, "f", items, count_bits, write_item)
    RecordsLike(like:, items:) ->
      bit_stream.write_array_like(writer, "f", items, like, write_item)
    Shapes(count_bits:, items:) ->
      bit_stream.write_array(writer, "f", items, count_bits, write_shape)
  }
}

fn write_item(writer: bit_stream.Writer, item: Item) -> bit_stream.Writer {
  writer
  |> bit_stream.write_unsigned("number", item.number, 5)
  |> bit_stream.write_wide_text("name", item.name)
}

fn read_item(reader: Reader) -> Result(#(Item, Reader), DecodeError) {
  use #(number, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  Ok(#(Item(number:, name:), reader))
}

/// Writes a shape as a record of the schema does: its kind as a fixed value,
/// then its data.
fn write_shape(writer: bit_stream.Writer, shape: Shape) -> bit_stream.Writer {
  case shape {
    Switch(on) ->
      writer
      |> bit_stream.write_constant("kind", 3, shape_kind_bits)
      |> bit_stream.write_unsigned("on", on, 1)
    Pair(#(first, second)) ->
      writer
      |> bit_stream.write_constant("kind", 17, shape_kind_bits)
      |> bit_stream.write_unsigned("first", first, 32)
      |> bit_stream.write_unsigned("second", second, 3)
    Run(values) ->
      writer
      |> bit_stream.write_constant("kind", 30, shape_kind_bits)
      |> bit_stream.write_unsigned_array("values", values, 4, 7)
  }
}

/// Reads a shape as a generated union does: the kind is peeked, and the
/// layout of that kind reads it, kind included.
fn read_shape(reader: Reader) -> Result(#(Shape, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, shape_kind_bits))
  case kind {
    3 -> result.map(read_switch(reader), pair.map_first(_, Switch))
    17 -> result.map(read_pair(reader), pair.map_first(_, Pair))
    30 -> result.map(read_run(reader), pair.map_first(_, Run))
    _ -> Error(bit_stream.UnexpectedValue(field: "kind", value: kind))
  }
}

fn read_switch(reader: Reader) -> Result(#(Int, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "kind",
    shape_kind_bits,
    3,
  ))
  bit_stream.read_unsigned(reader, 1)
}

fn read_pair(reader: Reader) -> Result(#(#(Int, Int), Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "kind",
    shape_kind_bits,
    17,
  ))
  use #(first, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(second, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  Ok(#(#(first, second), reader))
}

fn read_run(reader: Reader) -> Result(#(List(Int), Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "kind",
    shape_kind_bits,
    30,
  ))
  bit_stream.read_unsigned_array(reader, 4, 7)
}

/// Reads the field `like` is from the reader: the same kind with the same
/// width, count or limit, holding the values read.
fn read(
  reader: Reader,
  like like: Field,
) -> Result(#(Field, Reader), DecodeError) {
  case like {
    Unsigned(bits:, ..) ->
      bit_stream.read_unsigned(reader, bits)
      |> map_field(Unsigned(bits:, value: _))
    UnsignedBelow(bits:, limit:, ..) ->
      bit_stream.read_unsigned_below(reader, "f", bits, limit)
      |> map_field(UnsignedBelow(bits:, limit:, value: _))
    Float32(..) ->
      bit_stream.read_float32_bits(reader) |> map_field(Float32(bits: _))
    WideText(..) ->
      bit_stream.read_wide_text(reader) |> map_field(WideText(text: _))
    CountedWideText(max_units:, ..) ->
      bit_stream.read_counted_wide_text(reader, max_units)
      |> map_field(CountedWideText(max_units:, text: _))
    Guid(..) -> bit_stream.read_guid(reader) |> map_field(Guid(bytes: _))
    Endpoint(..) ->
      bit_stream.read_endpoint(reader) |> map_field(Endpoint(endpoint: _))
    RawBytes(bytes:) ->
      bit_stream.read_raw_bytes(reader, bit_array.byte_size(bytes))
      |> map_field(RawBytes(bytes: _))
    WholeFrame(..) ->
      bit_stream.read_whole_frame(reader) |> map_field(WholeFrame(frame: _))
    WideTexts(count_bits:, ..) ->
      bit_stream.read_wide_texts(reader, count_bits)
      |> map_field(WideTexts(count_bits:, texts: _))
    UnsignedArray(count_bits:, bits:, ..) ->
      bit_stream.read_unsigned_array(reader, count_bits, bits)
      |> map_field(UnsignedArray(count_bits:, bits:, items: _))
    Float32Array(count_bits:, ..) ->
      bit_stream.read_float32_array(reader, count_bits)
      |> map_field(Float32Array(count_bits:, items: _))
    UnsignedArrayLike(bits:, items:) ->
      bit_stream.read_unsigned_array_like(reader, items, bits)
      |> map_field(UnsignedArrayLike(bits:, items: _))
    Constant(bits:, value:) ->
      bit_stream.read_constant(reader, "f", bits, value)
      |> result.map(fn(reader) { #(Constant(bits:, value:), reader) })
    Records(count_bits:, ..) ->
      bit_stream.read_array(reader, count_bits, read_item)
      |> map_field(Records(count_bits:, items: _))
    RecordsLike(like:, ..) ->
      bit_stream.read_array_like(reader, like, read_item)
      |> map_field(RecordsLike(like:, items: _))
    Shapes(count_bits:, ..) ->
      bit_stream.read_array(reader, count_bits, read_shape)
      |> map_field(Shapes(count_bits:, items: _))
  }
}

fn map_field(
  read: Result(#(a, Reader), DecodeError),
  field: fn(a) -> Field,
) -> Result(#(Field, Reader), DecodeError) {
  result.map(read, fn(found) { #(field(found.0), found.1) })
}

// ---- the generators ----

/// A field of any kind.
fn any_field() -> Generator(Field) {
  qcheck.from_generators(unsigned_field(), [
    unsigned_below_field(),
    float32_field(),
    wide_text_field(),
    counted_wide_text_field(),
    guid_field(),
    endpoint_field(),
    raw_bytes_field(),
    whole_frame_field(),
    wide_texts_field(),
    unsigned_array_field(),
    float32_array_field(),
    unsigned_array_like_field(),
    constant_field(),
    records_field(),
    records_like_field(),
    shapes_field(),
  ])
}

/// A width in bits, 1 to 64.
fn width() -> Generator(Int) {
  qcheck.bounded_int(from: 1, to: 64)
}

/// An unsigned value of `bits` bits (0 to 64), every pattern of its bits
/// reachable, with 0 and the largest value drawn more often. qcheck draws an
/// integer from at most 32 bits, so a value of more than 32 bits is two draws.
fn unsigned_of(bits: Int) -> Generator(Int) {
  let largest = int.bitwise_shift_left(1, bits) - 1
  let anywhere = case bits > 32 {
    False -> qcheck.bounded_int(from: 0, to: largest)
    True -> {
      use high <- qcheck.bind(unsigned_of(bits - 32))
      use low <- qcheck.map(unsigned_of(32))
      high * 4_294_967_296 + low
    }
  }
  qcheck.from_weighted_generators(#(8, anywhere), [
    #(1, qcheck.constant(0)),
    #(1, qcheck.constant(largest)),
  ])
}

fn unsigned_field() -> Generator(Field) {
  use bits <- qcheck.bind(width())
  use value <- qcheck.map(unsigned_of(bits))
  Unsigned(bits:, value:)
}

fn unsigned_below_field() -> Generator(Field) {
  use bits <- qcheck.bind(qcheck.bounded_int(from: 1, to: 32))
  use limit <- qcheck.bind(qcheck.bounded_int(
    from: 1,
    to: int.bitwise_shift_left(1, bits),
  ))
  use value <- qcheck.map(qcheck.bounded_int(from: 0, to: limit - 1))
  UnsignedBelow(bits:, limit:, value:)
}

fn float32_field() -> Generator(Field) {
  qcheck.map(unsigned_of(32), fn(bits) { Float32(bits:) })
}

/// A character of a text: mostly ASCII, some of the basic plane, some above
/// it, so a text's UTF-16 units and its characters differ. With `zero`, the
/// character U+0000 can come.
fn character(zero zero: Bool) -> Generator(UtfCodepoint) {
  let first = case zero {
    True -> 0
    False -> 1
  }
  qcheck.from_weighted_generators(
    #(6, qcheck.bounded_codepoint(from: first, to: 126)),
    [
      #(2, qcheck.bounded_codepoint(from: 0x80, to: 0xD7FF)),
      #(2, qcheck.bounded_codepoint(from: 0x10000, to: 0x10FFFF)),
    ],
  )
}

/// How many characters a text holds: usually few, sometimes enough for more
/// than 127 UTF-16 units, so the 15-bit count is used.
fn text_length() -> Generator(Int) {
  qcheck.from_weighted_generators(#(7, qcheck.bounded_int(from: 0, to: 40)), [
    #(1, qcheck.bounded_int(from: 100, to: 300)),
  ])
}

fn wide_text_of() -> Generator(String) {
  qcheck.generic_string(character(zero: True), text_length())
}

fn wide_text_field() -> Generator(Field) {
  qcheck.map(wide_text_of(), fn(text) { WideText(text:) })
}

fn counted_wide_text_field() -> Generator(Field) {
  use max_units <- qcheck.bind(qcheck.bounded_int(from: 2, to: 250))
  use text <- qcheck.map(qcheck.generic_string(
    character(zero: False),
    qcheck.bounded_int(from: 0, to: max_units / 2),
  ))
  CountedWideText(max_units:, text:)
}

fn guid_field() -> Generator(Field) {
  qcheck.map(qcheck.fixed_size_byte_aligned_bit_array(16), fn(bytes) {
    Guid(bytes:)
  })
}

fn endpoint_field() -> Generator(Field) {
  use address <- qcheck.bind(unsigned_of(32))
  use port <- qcheck.map(unsigned_of(16))
  Endpoint(endpoint: bit_stream.Endpoint(address:, port:))
}

fn raw_bytes_field() -> Generator(Field) {
  use count <- qcheck.bind(qcheck.bounded_int(from: 1, to: 40))
  use bytes <- qcheck.map(qcheck.fixed_size_byte_aligned_bit_array(count))
  RawBytes(bytes:)
}

fn whole_frame_field() -> Generator(Field) {
  use count <- qcheck.bind(qcheck.bounded_int(from: 0, to: 300))
  use body <- qcheck.map(qcheck.fixed_size_byte_aligned_bit_array(count))
  WholeFrame(frame: <<{ 4 + count }:size(32)-little, body:bits>>)
}

/// A count of 1 to 16 bits and a list that count can hold, at most 6 long.
fn counted(items: Generator(a)) -> Generator(#(Int, List(a))) {
  use count_bits <- qcheck.bind(qcheck.bounded_int(from: 3, to: 16))
  use list <- qcheck.map(qcheck.generic_list(
    items,
    qcheck.bounded_int(from: 0, to: 6),
  ))
  #(count_bits, list)
}

fn wide_texts_field() -> Generator(Field) {
  use #(count_bits, texts) <- qcheck.map(counted(wide_text_of()))
  WideTexts(count_bits:, texts:)
}

fn unsigned_array_field() -> Generator(Field) {
  use bits <- qcheck.bind(width())
  use #(count_bits, items) <- qcheck.map(counted(unsigned_of(bits)))
  UnsignedArray(count_bits:, bits:, items:)
}

fn float32_array_field() -> Generator(Field) {
  use #(count_bits, items) <- qcheck.map(counted(unsigned_of(32)))
  Float32Array(count_bits:, items:)
}

fn unsigned_array_like_field() -> Generator(Field) {
  use bits <- qcheck.bind(width())
  use items <- qcheck.map(qcheck.generic_list(
    unsigned_of(bits),
    qcheck.bounded_int(from: 1, to: 6),
  ))
  UnsignedArrayLike(bits:, items:)
}

fn constant_field() -> Generator(Field) {
  use bits <- qcheck.bind(width())
  use value <- qcheck.map(unsigned_of(bits))
  Constant(bits:, value:)
}

fn item_of() -> Generator(Item) {
  use number <- qcheck.bind(unsigned_of(5))
  use name <- qcheck.map(wide_text_of())
  Item(number:, name:)
}

fn records_field() -> Generator(Field) {
  use #(count_bits, items) <- qcheck.map(counted(item_of()))
  Records(count_bits:, items:)
}

/// Records as many as the list that counts them, none included: the list is of
/// 32-bit values, as the commands' lists are.
fn records_like_field() -> Generator(Field) {
  use items <- qcheck.bind(qcheck.generic_list(
    item_of(),
    qcheck.bounded_int(from: 0, to: 6),
  ))
  use like <- qcheck.map(qcheck.generic_list(
    unsigned_of(32),
    qcheck.constant(list.length(items)),
  ))
  RecordsLike(like:, items:)
}

/// A shape of any of the three layouts.
fn shape_of() -> Generator(Shape) {
  let switch = qcheck.map(unsigned_of(1), Switch)
  let two = {
    use first <- qcheck.bind(unsigned_of(32))
    use second <- qcheck.map(unsigned_of(3))
    Pair(#(first, second))
  }
  let run =
    qcheck.generic_list(unsigned_of(7), qcheck.bounded_int(from: 0, to: 6))
    |> qcheck.map(Run)
  qcheck.from_generators(switch, [two, run])
}

fn shapes_field() -> Generator(Field) {
  use #(count_bits, items) <- qcheck.map(counted(shape_of()))
  Shapes(count_bits:, items:)
}

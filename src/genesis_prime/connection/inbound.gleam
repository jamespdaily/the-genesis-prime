//// What a connection does with the bytes its socket read: the rule of the
//// socket owner. The bytes join those left over from the last read, are cut
//// into frames, and each frame takes a token from the connection's bucket
//// before it is handed on. The first thing that breaks a limit ends the
//// connection, and the frames before it are still handed on, in order.
////
//// The size cap is the frame's own: no frame is over `frame.size_limit`, and
//// a length over it is refused as soon as its 4 bytes arrive, so the bytes
//// held between reads never reach one frame's size.

import genesis_prime/connection/frame.{type Frame, type FrameError}
import genesis_prime/connection/rate_limit.{type Rate, type RateExceeded}
import gleam/bit_array
import gleam/int
import gleam/list

/// A connection's inbound state: the start of a frame that has not fully
/// arrived, and the rate bucket.
pub opaque type Inbound {
  Inbound(leftover: BitArray, bucket: rate_limit.Bucket)
}

/// Why a connection ends because of what it received.
pub type EndReason {
  /// The bytes are not a frame.
  BadFrame(error: FrameError)
  /// The frames came faster than the rate allows.
  TooFast(exceeded: RateExceeded)
}

/// What the owner carries out, in order.
pub type Effect {
  /// Hand a complete frame to the connection's handler.
  Deliver(frame: Frame)
  /// End the connection: close the socket and log the reason.
  End(reason: EndReason)
}

/// A connection that has received nothing, with a full bucket of this rate.
pub fn new(rate rate: Rate, now_milliseconds now_milliseconds: Int) -> Inbound {
  Inbound(leftover: <<>>, bucket: rate_limit.new(rate:, now_milliseconds:))
}

/// The effects of `received`, which arrived at `now_milliseconds`, and the
/// state after it. After an `End` effect there are no more effects.
pub fn receive(
  inbound inbound: Inbound,
  received received: BitArray,
  now_milliseconds now_milliseconds: Int,
) -> #(Inbound, List(Effect)) {
  let #(frames, outcome) =
    frame.split(received: bit_array.append(inbound.leftover, received))
  let #(bucket, delivered) =
    take_tokens(
      bucket: inbound.bucket,
      frames:,
      now_milliseconds:,
      delivered: [],
    )
  case delivered, outcome {
    #(effects, Error(exceeded)), _ -> #(
      Inbound(..inbound, bucket:),
      list.append(effects, [End(TooFast(exceeded))]),
    )
    #(effects, Ok(Nil)), Ok(leftover) -> #(Inbound(leftover:, bucket:), effects)
    #(effects, Ok(Nil)), Error(error) -> #(
      Inbound(..inbound, bucket:),
      list.append(effects, [End(BadFrame(error))]),
    )
  }
}

/// Takes a token for each frame in order, giving a `Deliver` effect for each
/// frame that got one, and the first rate error if a frame did not.
fn take_tokens(
  bucket bucket: rate_limit.Bucket,
  frames frames: List(Frame),
  now_milliseconds now_milliseconds: Int,
  delivered delivered: List(Effect),
) -> #(rate_limit.Bucket, #(List(Effect), Result(Nil, RateExceeded))) {
  case frames {
    [] -> #(bucket, #(list.reverse(delivered), Ok(Nil)))
    [frame, ..rest] ->
      case rate_limit.take(bucket:, now_milliseconds:) {
        Ok(bucket) ->
          take_tokens(bucket:, frames: rest, now_milliseconds:, delivered: [
            Deliver(frame),
            ..delivered
          ])
        Error(exceeded) -> #(
          bucket,
          #(list.reverse(delivered), Error(exceeded)),
        )
      }
  }
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  case reason {
    BadFrame(error:) -> describe_frame_error(error)
    TooFast(exceeded: rate_limit.RateExceeded(rate:)) ->
      "frames came faster than "
      <> int.to_string(rate.frames_per_second)
      <> " a second with a burst of "
      <> int.to_string(rate.burst)
  }
}

fn describe_frame_error(error: FrameError) -> String {
  case error {
    frame.LengthOverLimit(length:) ->
      "frame length "
      <> int.to_string(length)
      <> " is over the limit of "
      <> int.to_string(frame.size_limit)
      <> " bytes"
    frame.LengthBelowHeader(length:) ->
      "frame length "
      <> int.to_string(length)
      <> " is below the "
      <> int.to_string(frame.header_size)
      <> " bytes of its header"
    frame.ShorterThanHeader(bytes:) ->
      "a frame of "
      <> int.to_string(bytes)
      <> " bytes is shorter than its header of "
      <> int.to_string(frame.header_size)
      <> " bytes"
    frame.LengthDisagrees(length:, bytes:) ->
      "frame length "
      <> int.to_string(length)
      <> " disagrees with its "
      <> int.to_string(bytes)
      <> " bytes"
    frame.MessageIdOutOfRange(message_id:) ->
      "message id " <> int.to_string(message_id) <> " does not fit in 16 bits"
  }
}

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
  todo as "an empty inbound state"
}

/// The effects of `received`, which arrived at `now_milliseconds`, and the
/// state after it. After an `End` effect there are no more effects.
pub fn receive(
  inbound inbound: Inbound,
  received received: BitArray,
  now_milliseconds now_milliseconds: Int,
) -> #(Inbound, List(Effect)) {
  todo as "cut the bytes into frames and take a token for each"
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  todo as "the reason in words"
}

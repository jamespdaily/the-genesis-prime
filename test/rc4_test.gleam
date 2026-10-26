//// The RC4 the NC platform library puts on the connection after the SRP
//// exchange: one state per direction, each keyed with the 64-byte session key,
//// running on across messages (record StsConnLib64.MT.dll!0x18003a7d0; vector
//// `vector.StsConnLib64.MT.dll!0x1800f7420.rc4`, the library's Rc4Crypt run
//// on Ghidra's p-code emulator and equal to standard RC4).

import genesis_prime/login/rc4
import login_vectors as vector
import message_support
import owned_test

fn counting_bytes_to_1f() -> BitArray {
  message_support.hex(
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
  )
}

fn started() -> rc4.Stream {
  let assert Ok(stream) = rc4.start(vector.session_key())
    as "this OTP has an RC4 cipher"
  stream
}

pub fn the_bytes_00_to_1f_encrypt_to_the_vectors_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert rc4.crypt(started(), counting_bytes_to_1f())
    == message_support.hex(
      "33b03353f0dd9c3bfc19692ca27a45434bb1faaff30a722ddd99edb384eae33c",
    )
    as "vector.StsConnLib64.MT.dll!0x1800f7420.rc4: the bytes 00..1f under K encrypt to 33b03353 ... eae33c"
}

pub fn the_stream_runs_on_across_calls_test() -> Nil {
  use <- owned_test.run(5000)
  let stream = started()
  let _written = rc4.crypt(stream, counting_bytes_to_1f())
  assert rc4.crypt(stream, <<0, 0, 0, 0>>) == message_support.hex("64470a37")
    as "vector.StsConnLib64.MT.dll!0x1800f7420.rc4: the next four zero bytes encrypt to 64470a37 on the same state"
}

pub fn a_second_stream_under_the_same_key_deciphers_the_first_test() -> Nil {
  use <- owned_test.run(5000)
  let sent = rc4.crypt(started(), counting_bytes_to_1f())
  assert rc4.crypt(started(), sent) == counting_bytes_to_1f()
    as "StsConnLib64.MT.dll!0x18003a7d0: the receiving state is keyed with the same key as the sending one, and RC4 deciphers with the same bytes"
}

pub fn a_key_of_no_bytes_does_not_start_a_stream_test() -> Nil {
  use <- owned_test.run(5000)
  assert rc4.start(<<>>) == Error(rc4.EmptyKey)
    as "RC4 is keyed with 1 to 256 bytes, and the library's key is the 64-byte session key (StsConnLib64.MT.dll!0x18003a7d0)"
}

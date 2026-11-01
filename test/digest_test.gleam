//// The SHA-256 digest as text (`genesis_prime/digest`). The expected value is
//// the SHA-256 of "abc" from FIPS 180-2, appendix B.1:
//// ba7816bf 8f01cfea 414140de 5dae2223 b00361a3 96177a9c b410ff61 f20015ad.

import genesis_prime/digest
import owned_test

pub fn the_sha256_of_bytes_is_lower_case_hex_test() -> Nil {
  use <- owned_test.run(5000)
  assert digest.sha256(<<"abc":utf8>>)
    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}

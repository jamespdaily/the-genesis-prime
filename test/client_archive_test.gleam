//// The client build the server is written for. The client's own build, 16042
//// (0x3eaa), is the constant returned by GetVersionInfo at 0x1406f8360. The
//// archive indexes' builds are read by the table extractor
//// (`setup_check/extract_tables.py`), whose tests plant each index.

import genesis_prime/client_archive
import owned_test

pub fn the_target_build_is_the_clients_own_build_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_archive.target_build == 16_042
    as "GetVersionInfo 0x1406f8360 returns nBuildNumber 16042 (0x3eaa)"
}

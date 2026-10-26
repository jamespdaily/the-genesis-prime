//// Reads the environment for tests that need the machine's client files.

import envoy

/// The value of an environment variable, or an error when it is not set.
pub fn get(name: String) -> Result(String, Nil) {
  envoy.get(name)
}

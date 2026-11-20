//// The folders of the client's extracted game tables and other files, for the tools
//// that read them: `GENESIS_TABLE_DIR`, else `tables` under the home folder; and for
//// the other files `GENESIS_CLIENT_FILES_DIR`, else `client-files` under the home
//// folder. The home folder is `GENESIS_HOME`, else `.genesis-prime` under the
//// user's home, else `.genesis-prime` in the working folder.

import envoy

/// The tools' home folder from the two environment variables that name it:
/// `GENESIS_HOME`, else `.genesis-prime` under `HOME`, else `.genesis-prime`.
pub fn home_from(
  genesis_home genesis_home: Result(String, Nil),
  user_home user_home: Result(String, Nil),
) -> String {
  case genesis_home, user_home {
    Ok(home), _ -> home
    Error(Nil), Ok(home) -> home <> "/.genesis-prime"
    Error(Nil), Error(Nil) -> ".genesis-prime"
  }
}

/// The tools' home folder, from the environment.
pub fn home() -> String {
  home_from(
    genesis_home: envoy.get("GENESIS_HOME"),
    user_home: envoy.get("HOME"),
  )
}

/// The folder of the client's extracted game tables.
pub fn path() -> String {
  case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) -> home() <> "/tables"
  }
}

/// The folder of the client's other extracted files, among them `en-US.bin`.
pub fn client_files_path() -> String {
  case envoy.get("GENESIS_CLIENT_FILES_DIR") {
    Ok(folder) -> folder
    Error(Nil) -> home() <> "/client-files"
  }
}

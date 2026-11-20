//// The files the dashboard serves besides its pages, by an allow-list: four of
//// the client's fonts and the dashboard's two stylesheets. A request's path
//// is matched whole against the list, so no other spelling of a name, a parent
//// folder or an encoded form reaches a file.
////
//// The fonts are in the client's `UI/Fonts` folder (`CubeOffcCond.ttf`,
//// `CubeOffcCondLight.ttf`, `segoeui.ttf`, `seguisb.ttf`), extracted by
//// `client_files.py extract`; no client file is copied. The stylesheets are in
//// `dev/dashboard`.

import gleam/list

/// The folder a served file is read from.
pub type Location {
  ClientFonts
  DashboardFolder
}

/// A file the dashboard serves: the request path it answers, the folder and
/// name it reads, and its `Content-Type`.
pub type Asset {
  Asset(path: String, location: Location, file_name: String, media_type: String)
}

/// Every file the dashboard serves.
pub fn assets() -> List(Asset) {
  [
    font("/art/cube-cond.ttf", "CubeOffcCond.ttf"),
    font("/art/cube-cond-light.ttf", "CubeOffcCondLight.ttf"),
    font("/art/segoe-ui.ttf", "segoeui.ttf"),
    font("/art/segoe-ui-semibold.ttf", "seguisb.ttf"),
    stylesheet("/style.css", "style.css"),
    stylesheet("/palette.css", "palette.css"),
  ]
}

fn font(path: String, file_name: String) -> Asset {
  Asset(path:, location: ClientFonts, file_name:, media_type: "font/ttf")
}

fn stylesheet(path: String, file_name: String) -> Asset {
  Asset(
    path:,
    location: DashboardFolder,
    file_name:,
    media_type: "text/css; charset=utf-8",
  )
}

/// The file a request path names, when the list holds it.
pub fn find(path path: String) -> Result(Asset, Nil) {
  list.find(assets(), fn(asset) { asset.path == path })
}

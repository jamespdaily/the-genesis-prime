//// The client build the server is written for. Every login and every
//// recording carries it, and the table extractor refuses an archive index of
//// any other build.

/// The client build this server is written against (GetVersionInfo at
/// 0x1406f8360 returns nBuildNumber 16042, 0x3eaa).
pub const target_build = 16_042

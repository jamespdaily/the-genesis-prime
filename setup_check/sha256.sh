# Sourced by dev/apply_migrations.sh, dev/client_data.sh and release/fetch_release.sh
# (bash or POSIX sh): defines sha256, and nothing else. It is a file of its own
# because setup_check/environment.sh, the other file both scripts could source,
# also reads the machine's env.sh and sets variables, which no script that sources this wants.

# sha256 FILE: the file's SHA-256 as lower-case hex, from whichever tool this
# machine has: sha256sum (Linux) or shasum (macOS).
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

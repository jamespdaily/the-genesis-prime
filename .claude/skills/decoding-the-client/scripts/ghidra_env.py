"""The pinned parts of the client query process, and where they live.

Every path comes from the environment, so nothing machine-specific is in the
repository. A wrong Ghidra version stops the process before it opens anything.
"""

import hashlib
import importlib.metadata
import sys
from dataclasses import dataclass
from pathlib import Path

GHIDRA_VERSION = "12.2"
GHIDRA_RELEASE_ZIP = "ghidra_12.2_PUBLIC_20261016.zip"
GHIDRA_RELEASE_SHA256 = "2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67"
JDK_MAJOR = 25
PYTHON_MINOR = (3, 13)
PYGHIDRA_VERSION = "3.2.0"

CLIENT_SHA256 = "565c2fa1a1cf4b08cf5a93e0bff90bf09bde5772d03615402132d72db5fe0b10"


@dataclass(frozen=True)
class Settings:
    ghidra_dir: Path  # GENESIS_GHIDRA_DIR: the unpacked official release
    project_dir: Path  # GENESIS_GHIDRA_PROJECT_DIR: holds the analysed project
    client_exe: Path  # WILDSTAR_CLIENT_EXE: WildStar64.exe
    java_home: Path  # JAVA_HOME: a JDK 25


class WrongVersion(Exception):
    """A pinned part is missing or has another version; the message names what was found."""


def settings_from_env(env) -> Settings:
    """Reads the four paths; a missing variable raises WrongVersion naming it."""
    values = {}
    for name in ("GENESIS_GHIDRA_DIR", "GENESIS_GHIDRA_PROJECT_DIR", "WILDSTAR_CLIENT_EXE", "JAVA_HOME"):
        if not env.get(name):
            raise WrongVersion("%s is not set" % name)
        values[name] = Path(env[name])
    return Settings(
        ghidra_dir=values["GENESIS_GHIDRA_DIR"],
        project_dir=values["GENESIS_GHIDRA_PROJECT_DIR"],
        client_exe=values["WILDSTAR_CLIENT_EXE"],
        java_home=values["JAVA_HOME"],
    )


def _properties(path: Path) -> dict[str, str]:
    try:
        text = path.read_text()
    except OSError as error:
        raise WrongVersion("cannot read %s: %s" % (path, error)) from error
    pairs = (line.split("=", 1) for line in text.splitlines() if "=" in line and not line.startswith("#"))
    return {k.strip(): v.strip() for k, v in pairs}


def ghidra_version(ghidra_dir: Path) -> str:
    """The `application.version` in the release's Ghidra/application.properties."""
    properties = _properties(ghidra_dir / "Ghidra" / "application.properties")
    if "application.version" not in properties:
        raise WrongVersion("%s names no application.version" % (ghidra_dir / "Ghidra" / "application.properties"))
    return properties["application.version"]


def _jdk_major(java_home: Path) -> str:
    properties = _properties(java_home / "release")
    return properties.get("JAVA_VERSION", "").strip('"').split(".")[0]


def check_parts(settings: Settings) -> None:
    """Raises WrongVersion unless Ghidra is GHIDRA_VERSION with a macOS arm64
    decompiler, the JDK is JDK_MAJOR, Python is PYTHON_MINOR, PyGhidra is
    PYGHIDRA_VERSION and the client's SHA-256 is CLIENT_SHA256."""
    found = ghidra_version(settings.ghidra_dir)
    if found != GHIDRA_VERSION:
        raise WrongVersion("Ghidra %s found at %s, %s required" % (found, settings.ghidra_dir, GHIDRA_VERSION))
    decompiler = settings.ghidra_dir / "Ghidra" / "Features" / "Decompiler" / "os" / "mac_arm_64" / "decompile"
    if not decompiler.is_file():
        raise WrongVersion("no macOS arm64 decompiler at %s" % decompiler)
    jdk = _jdk_major(settings.java_home)
    if jdk != str(JDK_MAJOR):
        raise WrongVersion("JDK %r found at %s, %d required" % (jdk, settings.java_home, JDK_MAJOR))
    if sys.version_info[:2] != PYTHON_MINOR:
        raise WrongVersion("Python %d.%d found, %d.%d required" % (*sys.version_info[:2], *PYTHON_MINOR))
    try:
        pyghidra = importlib.metadata.version("pyghidra")
    except importlib.metadata.PackageNotFoundError as error:
        raise WrongVersion("PyGhidra is not installed, %s required" % PYGHIDRA_VERSION) from error
    if pyghidra != PYGHIDRA_VERSION:
        raise WrongVersion("PyGhidra %s found, %s required" % (pyghidra, PYGHIDRA_VERSION))
    digest = hashlib.sha256()
    try:
        with open(settings.client_exe, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                digest.update(chunk)
    except OSError as error:
        raise WrongVersion("cannot read the client at %s: %s" % (settings.client_exe, error)) from error
    if digest.hexdigest() != CLIENT_SHA256:
        raise WrongVersion("the client at %s has SHA-256 %s, %s required" % (settings.client_exe, digest.hexdigest(), CLIENT_SHA256))

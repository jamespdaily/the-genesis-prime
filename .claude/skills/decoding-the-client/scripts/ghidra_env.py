"""The pinned parts of the client query process, and where they live.

Every path comes from the environment, so nothing machine-specific is in the
repository. A wrong Ghidra version stops the process before it opens anything.
"""

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
    raise NotImplementedError


def ghidra_version(ghidra_dir: Path) -> str:
    """The `application.version` in the release's Ghidra/application.properties."""
    raise NotImplementedError


def check_parts(settings: Settings) -> None:
    """Raises WrongVersion unless Ghidra is GHIDRA_VERSION with a macOS arm64
    decompiler, the JDK is JDK_MAJOR, Python is PYTHON_MINOR, PyGhidra is
    PYGHIDRA_VERSION and the client's SHA-256 is CLIENT_SHA256."""
    raise NotImplementedError

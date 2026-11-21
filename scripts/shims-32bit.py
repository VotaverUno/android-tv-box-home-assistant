"""shims32.py - pure-python shims for rust-built Home Assistant deps (armv7 / Termux).

Run inside the HA venv:  python shims32.py

Packages shimmed (versions pinned to what HA 2026.11.1 requires):
  orjson 3.13.0          -> strict stdlib-based JSON encoder/decoder (+Fragment, OPT_*)
  ulid-transform 2.2.9   -> pure python ULID (Crockford base32)
  fnv-hash-fast 2.0.3    -> pure python FNV-1/1a 32/64
  uv 0.13.6              -> `python -m uv pip ...` forwarded to pip
"""
import pathlib
import shutil
import sys
import sysconfig

SITE = pathlib.Path(sysconfig.get_paths()["purelib"])

METADATA = """Metadata-Version: 2.1
Name: {name}
Version: {version}
Summary: pure-python shim for {name} (32-bit Termux fallback)
"""

WHEEL = """Wheel-Version: 1.0
Generator: shims32
Root-Is-Purelib: true
Tag: py3-none-any
"""


def write_pkg(dist_name: str, version: str, module_name: str, files: dict[str, str]) -> None:
    mod_dir = SITE / module_name
    for stale in SITE.glob(f"{dist_name.replace('-', '_')}-*.dist-info"):
        shutil.rmtree(stale, ignore_errors=True)
    mod_dir.mkdir(parents=True, exist_ok=True)
    for rel, content in files.items():
        p = mod_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
    dist = SITE / f"{dist_name.replace('-', '_')}-{version}.dist-info"
    dist.mkdir(parents=True, exist_ok=True)
    (dist / "METADATA").write_text(METADATA.format(name=dist_name, version=version), encoding="utf-8")
    (dist / "WHEEL").write_text(WHEEL, encoding="utf-8")
    (dist / "RECORD").write_text("", encoding="utf-8")
    print(f"shim installed: {dist_name}=={version} -> {mod_dir}")


ORJSON = '''"""Pure-python shim for orjson (32-bit Android fallback).

Implements a strict JSON encoder (valid JSON only: NaN/Infinity -> null), the
Fragment wrapper used by Home Assistant's websocket api, and the OPT_* flags.
"""
import dataclasses as _dc
import datetime as _dt
import decimal as _dec
import json as _json
import math as _math
import pathlib as _pathlib
import uuid as _uuid

__version__ = "3.13.0"


class JSONDecodeError(_json.JSONDecodeError):
    pass


OPT_APPEND_NEWLINE = 1024
OPT_INDENT_2 = 1
OPT_NAIVE_UTC = 2
OPT_NON_STR_KEYS = 4
OPT_OMIT_MICROSECONDS = 8
OPT_PASSTHROUGH_DATACLASS = 16
OPT_PASSTHROUGH_DATETIME = 32
OPT_PASSTHROUGH_SUBCLASS = 64
OPT_SERIALIZE_DATACLASS = 128
OPT_SERIALIZE_NUMPY = 256
OPT_SERIALIZE_UUID = 512
OPT_SORT_KEYS = 1024
OPT_STRICT_INTEGER = 2048
OPT_UTC_Z = 4096


class Fragment:
    """Pre-serialized JSON embedded verbatim (mimics orjson.Fragment)."""

    __slots__ = ("value",)

    def __init__(self, value):
        if isinstance(value, (bytes, bytearray, memoryview)):
            value = bytes(value).decode("utf-8")
        if not isinstance(value, str):
            raise TypeError("Fragment value must be str or bytes")
        self.value = value


def _default(o):
    if isinstance(o, (_dt.datetime, _dt.date, _dt.time)):
        return o.isoformat()
    if isinstance(o, _uuid.UUID):
        return str(o)
    if isinstance(o, _dec.Decimal):
        return float(o)
    if isinstance(o, (set, frozenset)):
        return list(o)
    if isinstance(o, (bytes, bytearray, memoryview)):
        return bytes(o).decode("utf-8", "replace")
    if isinstance(o, _pathlib.PurePath):
        return str(o)
    if _dc.is_dataclass(o) and not isinstance(o, type):
        return _dc.asdict(o)
    raise TypeError(f"Type is not JSON serializable: {type(o).__name__}")


def _enc(o, handler, depth=0):
    if depth > 200:
        raise ValueError("circular reference detected")
    if o is None:
        return "null"
    if o is True:
        return "true"
    if o is False:
        return "false"
    if isinstance(o, str):
        return _json.dumps(o, ensure_ascii=False)
    if isinstance(o, int):
        return str(o)
    if isinstance(o, float):
        return "null" if not _math.isfinite(o) else repr(o)
    if isinstance(o, Fragment):
        return o.value
    if isinstance(o, dict):
        parts = []
        for key, value in o.items():
            if isinstance(key, str):
                key_txt = _json.dumps(key, ensure_ascii=False)
            elif key is None:
                key_txt = '"null"'
            elif key is True:
                key_txt = '"true"'
            elif key is False:
                key_txt = '"false"'
            elif isinstance(key, (int, float)):
                # JSON object keys MUST be quoted strings (orjson OPT_NON_STR_KEYS
                # converts 1 -> "1" as well)
                key_txt = _json.dumps(str(key))
            else:
                key_txt = _json.dumps(str(key), ensure_ascii=False)
            parts.append(key_txt + ":" + _enc(value, handler, depth + 1))
        return "{" + ",".join(parts) + "}"
    if isinstance(o, (list, tuple)):
        return "[" + ",".join(_enc(item, handler, depth + 1) for item in o) + "]"
    converted = handler(o)
    if converted is o:
        raise TypeError(f"Type is not JSON serializable: {type(o).__name__}")
    return _enc(converted, handler, depth + 1)


def loads(obj, /):
    if isinstance(obj, (bytes, bytearray, memoryview)):
        obj = bytes(obj).decode("utf-8")
    try:
        return _json.loads(obj)
    except _json.JSONDecodeError as err:
        raise JSONDecodeError(err.msg, err.doc, err.pos) from None


def dumps(obj, /, default=None, option=None, **kwargs):
    # NOTE: option is accepted for API compatibility. We deliberately always use the
    # strict encoder below (no stdlib json path), because Home Assistant passes
    # option=OPT_INDENT_2 | OPT_NON_STR_KEYS when writing registries and the data
    # contains orjson.Fragment values (from cached JSON fragments) that stdlib json
    # cannot handle. Output is valid JSON either way; only pretty-printing differs.
    handler = default if default is not None else _default
    return _enc(obj, handler).encode("utf-8")
'''

ULID = '''"""Pure-python shim for ulid-transform (32-bit Android fallback)."""
import os
import time

__version__ = "2.2.9"

_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_LOOKUP = {c: i for i, c in enumerate(_ALPHABET)}
_LOOKUP.update({"I": 1, "L": 1, "O": 0, "U": 0})


def _encode(value: int) -> str:
    return "".join(_ALPHABET[(value >> shift) & 0x1F] for shift in range(125, -1, -5))


def _decode(text: str) -> int:
    if not isinstance(text, str) or len(text) != 26:
        raise ValueError("ULID must be a 26 character string")
    value = 0
    for ch in text.upper():
        try:
            value = (value << 5) | _LOOKUP[ch]
        except KeyError:
            raise ValueError(f"Invalid ULID character: {ch}") from None
    return value


def _random_bits() -> int:
    return int.from_bytes(os.urandom(10), "big")


def ulid_now() -> str:
    return _encode((int(time.time() * 1000) << 80) | _random_bits())


def ulid_at_time(timestamp: float) -> str:
    return _encode((int(timestamp * 1000) << 80) | _random_bits())


def ulid_now_bytes() -> bytes:
    return ((int(time.time() * 1000) << 80) | _random_bits()).to_bytes(16, "big")


def ulid_hex() -> str:
    return ulid_now_bytes().hex()


def ulid_to_bytes(value: str) -> bytes:
    return _decode(value).to_bytes(16, "big")


def ulid_to_bytes_or_none(value):
    try:
        return ulid_to_bytes(value)
    except (TypeError, ValueError):
        return None


def bytes_to_ulid(value: bytes) -> str:
    if not isinstance(value, (bytes, bytearray)) or len(value) != 16:
        raise ValueError("ULID bytes must be 16 bytes")
    return _encode(int.from_bytes(bytes(value), "big"))


def bytes_to_ulid_or_none(value):
    try:
        return bytes_to_ulid(value)
    except (TypeError, ValueError):
        return None
'''

FNV = '''"""Pure-python shim for fnv-hash-fast (32-bit Android fallback)."""
__version__ = "2.0.3"

FNV1_32_OFFSET = 0x811C9DC5
FNV1_64_OFFSET = 0xCBF29CE484222325
FNV1_32_PRIME = 0x01000193
FNV1_64_PRIME = 0x100000001B3
_M32 = 0xFFFFFFFF
_M64 = 0xFFFFFFFFFFFFFFFF


def _data(value) -> bytes:
    if isinstance(value, str):
        return value.encode("utf-8")
    if isinstance(value, (bytes, bytearray, memoryview)):
        return bytes(value)
    raise TypeError("expected str or bytes")


def fnv1a_32(data, seed=FNV1_32_OFFSET) -> int:
    h = seed & _M32
    for byte in _data(data):
        h = ((h ^ byte) * FNV1_32_PRIME) & _M32
    return h


def fnv1_32(data, seed=FNV1_32_OFFSET) -> int:
    h = seed & _M32
    for byte in _data(data):
        h = ((h * FNV1_32_PRIME) & _M32) ^ byte
    return h


def fnv1a_64(data, seed=FNV1_64_OFFSET) -> int:
    h = seed & _M64
    for byte in _data(data):
        h = ((h ^ byte) * FNV1_64_PRIME) & _M64
    return h


def fnv1_64(data, seed=FNV1_64_OFFSET) -> int:
    h = seed & _M64
    for byte in _data(data):
        h = ((h * FNV1_64_PRIME) & _M64) ^ byte
    return h


def fnv1a_32_str(data) -> int:
    return fnv1a_32(data)


def fnv1a_64_str(data) -> int:
    return fnv1a_64(data)
'''

UV_INIT = '''"""Pure-python shim for uv: `python -m uv pip ...` is forwarded to pip."""
__version__ = "0.13.6"
'''

UV_MAIN = '''"""Forward the small `uv pip` surface Home Assistant uses to pip.

Speed matters on this box: HA calls us whenever an integration lists requirements,
and a real network round-trip can cost 60s x 3 retries. If the requested
requirement is already satisfied we short-circuit and exit 0.
"""
import subprocess
import sys

try:
    from importlib.metadata import PackageNotFoundError, version
    from packaging.requirements import Requirement
except Exception:  # noqa: BLE001
    Requirement = None


def _already_satisfied(pkg):
    """True if the requirement string is already installed/satisfied."""
    if Requirement is None:
        return False
    try:
        req = Requirement(pkg)
    except Exception:  # noqa: BLE001
        return False
    try:
        installed = version(req.name)
    except PackageNotFoundError:
        return False
    try:
        return not req.specifier or req.specifier.contains(installed, prereleases=True)
    except Exception:  # noqa: BLE001
        return False


def _forward(argv):
    args = list(argv)
    if args[:1] != ["pip"]:
        print("this uv shim only supports: python -m uv pip install|list", file=sys.stderr)
        return 2
    sub = args[1] if len(args) > 1 else "list"
    rest = args[2:]
    if sub == "install":
        # --constraint <file> must be forwarded as pip -c <file>; other uv-only flags dropped.
        filtered = []
        constraints = []
        skip_next = False
        for token in rest:
            if skip_next:
                skip_next = False
                continue
            if token in ("--index-strategy", "--index", "--extra-index-url", "--python"):
                skip_next = True
                continue
            if token == "--constraint":
                skip_next = True
                continue
            if token in ("--quiet", "--upgrade"):
                continue
            if token.startswith("-"):
                continue
            filtered.append(token)
        # rebuild: HA passes the constraint file as a separate argument
        for i, token in enumerate(rest):
            if token == "--constraint" and i + 1 < len(rest):
                constraints.append(rest[i + 1])
        if filtered and all(_already_satisfied(pkg) for pkg in filtered):
            return 0
        pip_args = ["install", "--quiet"]
        for c in constraints:
            pip_args.extend(["-c", c])
        pip_args.extend(filtered)
        return subprocess.call([sys.executable, "-m", "pip"] + pip_args)
    if sub == "install":
        pip_args = ["install"]
        skip_next = False
        for token in rest:
            if skip_next:
                skip_next = False
                continue
            if token in ("--index-strategy", "--index", "--extra-index-url", "--python"):
                skip_next = True
                continue
            if token in ("--quiet", "--upgrade", "--constraint"):
                pip_args.append(token)
            elif token.startswith("-"):
                continue
            else:
                pip_args.append(token)
        cmd = [sys.executable, "-m", "pip"] + pip_args
    elif sub == "list":
        cmd = [sys.executable, "-m", "pip", "list", "--format", "json"]
    else:
        print(f"this uv shim does not support: {sub}", file=sys.stderr)
        return 2
    return subprocess.call(cmd)


if __name__ == "__main__":
    sys.exit(_forward(sys.argv[1:]))
'''


def main() -> int:
    write_pkg("orjson", "3.13.0", "orjson", {"__init__.py": ORJSON})
    write_pkg("ulid-transform", "2.2.9", "ulid_transform", {"__init__.py": ULID})
    write_pkg("fnv-hash-fast", "2.0.3", "fnv_hash_fast", {"__init__.py": FNV})
    write_pkg("uv", "0.13.6", "uv", {"__init__.py": UV_INIT, "__main__.py": UV_MAIN})
    print("all shims installed into", SITE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Fail if a credential-shaped string is committed to a tracked file.

Written 2026-09-15 after the 2.13.2 secret-redaction fix was tested with the *live*
lab webhook secret, putting a 33-character fragment of it into
`test_webhook_notification_types.py` and an 8+8-character fragment into the 09-14
evidence file — both tracked and pushed.

Deliberately a regex over `git ls-files`, not a secret-scanning dependency. It catches
the two shapes that actually reached this repo:

  1. a long lowercase-hex run (>= 16 chars), and
  2. any credential keyword assigned a value that is not an obvious placeholder.

Known ceiling: an 8-character hex fragment on its own is indistinguishable from an
id and is NOT caught. Rule 2 catches it only when a keyword sits next to it. Upgrade
path if that ever bites: entropy scoring, or gitleaks in CI.
"""
import re
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]

# Long lowercase-hex run — the shape of every secret this project generates
# (`openssl rand -hex 32`).
HEX_RUN = re.compile(r"(?<![0-9a-zA-Z])[0-9a-f]{16,}(?![0-9a-zA-Z])")

# secret=<value> / "api_key": "<value>" — LITERALS ONLY. An unquoted value is
# required to be pure hex, which is the shape `openssl rand -hex 32` produces and the
# shape the leaked fragments had; a quoted value may be any long random-looking run.
# Without the literal requirement this fires on ordinary code such as
# `password=encodeURIComponent(pin)` and `apiKey: server.apiKey`, and a check that
# cries wolf gets deleted.
_KW = (r"(?i)\b(secret|token|password|passwd|pwd|api[_-]?key|apikey|private[_-]?key)\b"
       r"\s*[=:]\s*")
KEYWORD_VALUE = re.compile(
    _KW + r"(?:"
          r"[\"'`]([A-Za-z0-9+/=_-]{16,})[\"'`]"   # quoted long run
          r"|([0-9a-f]{8,})(?![0-9a-zA-Z])"          # bare hex, >= 8 chars
          r")"
)

# Anything obviously not a live credential.
PLACEHOLDER = re.compile(
    r"(?i)^("
    r"0+|x+|deadbeef(?:deadbeef)*|abc123|changeme|redacted|none|null|true|false"
    r"|your[_-].*|my[_-].*|test.*|fake.*|dummy.*|sample.*|example.*|placeholder.*"
    r"|(.)\2{4,}"              # one character repeated: AAAAAAAAAA
    r"|[a-z]+(?:-[a-z0-9]+)+"     # lowercase-hyphenated slug: secret-api-key-12345.
                                # Generated secrets in this project are hex or
                                # base64 and never look like written words.
    r"|[a-f0-9]{40}"            # a git commit SHA
    r")$"
)

# Generated or vendored files whose long runs are not ours to police.
SKIP_SUFFIX = {".pbxproj", ".svg", ".png", ".jpg", ".jpeg", ".ico", ".lock", ".pdf"}
SKIP_PATH = (
    "pwa/package-lock.json",
    "docs/benem-runtime-architecture.",
    # Build caches that are untracked but not ignored either. They hold hashes, not
    # credentials. That they show up here at all is a .gitignore gap, which is a
    # separate open item — remove these entries once it is closed.
    ".vite/", "dist/", "coverage/", ".pytest_cache/",
)


def _tracked_text_files():
    # -c: files in the index (so a `git add`ed new file is covered)
    # -o --exclude-standard: files on disk that are not yet added and not ignored
    #
    # Plain `git ls-files` lists only the index, which gave every NEW file a free
    # pass on the commit that introduced it — run the suite before `git add` and the
    # scanner could not see the file at all. This one proved it on itself. A file
    # created with a live credential inside would have had exactly one free run.
    out = subprocess.run(["git", "ls-files", "-c", "-o", "--exclude-standard"],
                         cwd=REPO, capture_output=True, text=True, check=True)
    for rel in dict.fromkeys(out.stdout.splitlines()):
        p = REPO / rel
        if p.suffix.lower() in SKIP_SUFFIX or rel.startswith(SKIP_PATH):
            continue
        try:
            yield rel, p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue


def _findings():
    out = []
    for rel, text in _tracked_text_files():
        for n, line in enumerate(text.splitlines(), 1):
            for m in HEX_RUN.finditer(line):
                if not PLACEHOLDER.match(m.group(0)):
                    out.append(f"{rel}:{n} long hex run ({len(m.group(0))} chars)")
            for m in KEYWORD_VALUE.finditer(line):
                val = m.group(2) or m.group(3)
                if not PLACEHOLDER.match(val):
                    out.append(f"{rel}:{n} {m.group(1)}= credential-shaped literal ({len(val)} chars)")
    return out


def test_no_credential_shaped_strings_in_tracked_files():
    found = _findings()
    assert not found, "credential-shaped strings in tracked files:\n  " + "\n  ".join(found)


# A detector's positive fixtures necessarily look like the thing it detects, so
# they are assembled at runtime from pieces that are individually below its own
# thresholds. That keeps THIS file inside the scan rather than exempting it — an
# exemption is where a real credential would eventually be pasted.
_H15 = "0123456789abcde"        # 15 hex chars: under the 16-char HEX_RUN threshold
_LONG_RUN = _H15 * 2 + "f"      # 31 chars once joined — credential-shaped
_HEAD8, _TAIL8 = "0123abcd", "89efdcba"


@pytest.mark.parametrize("line,caught", [
    # The two shapes that actually reached this repo, in their original form.
    ('line = \'POST /webhook?secret=' + _LONG_RUN + ' HTTP/1.1"\'', True),
    # 8 leading + ellipsis + 8 trailing — the evidence-file shape.
    ('INFO: "POST /webhook?secret=' + _HEAD8 + '\u2026' + _TAIL8 + ' HTTP/1.1" 200 OK', True),
    # What they were replaced with.
    ('line = \'POST /webhook?secret=' + "deadbeef" * 8 + ' HTTP/1.1"\'', False),
    ('assert "deadbeef" not in out', False),
    # Everyday lines that must not trip it.
    ('commit a0d8d70 docs(shared): drop the superseded architecture SVG', False),
    ('resp = client.post("/webhook?secret=no-devices-yet", json=payload)', False),
    ('APNS_PRIVATE_KEY_B64=<your-base64-key>', False),
    ('password=encodeURIComponent(pin)', False),
    ('apiKey: server.apiKey,', False),
])
def test_detector_catches_the_shapes_that_reached_this_repo(line, caught):
    hit = (any(not PLACEHOLDER.match(m.group(0)) for m in HEX_RUN.finditer(line))
           or any(not PLACEHOLDER.match(m.group(2) or m.group(3)) for m in KEYWORD_VALUE.finditer(line)))
    assert hit is caught, line

#!/usr/bin/env python3
"""
generate-licenses.py — Assemble third-party license credits for the About window.

Reads Tuist/Package.resolved, fetches license information for each pinned
dependency from the GitHub API, and writes ScoreEdit/Resources/LICENSES.md.
ScoreEdit/Resources is a buildable folder, so the file is bundled
automatically.

Usage:
    scripts/generate-licenses.py
    mise run get_licenses

A GitHub token is looked up, in order, from:
  1. The GITHUB_TOKEN environment variable.
  2. The 1Password secret reference in SECRETS.json's `github_token_op_ref`,
     read with `op read`.
  3. The GitHub CLI (`gh auth token`).
Authenticated requests are limited to 5000/hr; unauthenticated to 60/hr.
"""

import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
RESOLVED_FILE = REPO_ROOT / "Tuist" / "Package.resolved"
SECRETS_FILE = REPO_ROOT / "SECRETS.json"
OUTPUT_FILE = REPO_ROOT / "ScoreEdit" / "Resources" / "LICENSES.md"
GITHUB_API = "https://api.github.com"


def github_request(path: str, token: str | None) -> dict:
    """Make a GitHub API request and return parsed JSON, or {} on error."""
    url = f"{GITHUB_API}{path}"
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "ScoreEdit-license-collector")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        # 404 is expected when probing for optional files like NOTICE.
        if exc.code != 404:
            print(f"  Warning: GitHub API error for {url}: {exc}", file=sys.stderr)
        return {}
    except Exception as exc:
        print(f"  Warning: request failed for {url}: {exc}", file=sys.stderr)
        return {}


def extract_github_owner_repo(url: str) -> tuple[str, str] | None:
    """Return (owner, repo) parsed from a GitHub URL, or None."""
    url = url.rstrip("/")
    if url.endswith(".git"):
        url = url[:-4]
    match = re.match(r"https?://github\.com/([^/]+)/([^/]+)$", url)
    if match:
        return match.group(1), match.group(2)
    return None


def extract_copyright_lines(text: str) -> list[str]:
    """Return lines that are actual copyright claims (not boilerplate).

    A real copyright claim starts with 'Copyright' or '©' (after optional
    leading whitespace/bullets) and contains a real four-digit year.  Lines
    like 'The above copyright notice…' or 'AUTHORS OR COPYRIGHT HOLDERS…'
    don't start with the keyword, and template lines like
    'Copyright [yyyy] [name]' lack a real year, so both are excluded.
    """
    starts_with_copyright = re.compile(
        r"^[\s\-\*•]*(?:Copyright|©)\b", re.IGNORECASE
    )
    has_real_year = re.compile(r"\b\d{4}\b")
    is_template = re.compile(r"\[yyyy\]", re.IGNORECASE)

    results = []
    for line in text.splitlines():
        stripped = line.strip()
        if (
            stripped
            and starts_with_copyright.match(stripped)
            and has_real_year.search(stripped)
            and not is_template.search(stripped)
        ):
            results.append(stripped)
    return results


NOTICE_FILENAMES = ["NOTICE", "NOTICE.txt", "NOTICE.md"]


def fetch_notice_copyright(owner: str, repo: str, token: str | None) -> list[str]:
    """Return copyright lines from a NOTICE file, or [] if none is found."""
    for filename in NOTICE_FILENAMES:
        data = github_request(f"/repos/{owner}/{repo}/contents/{filename}", token)
        raw_content = data.get("content", "") if data else ""
        if not raw_content:
            continue
        try:
            decoded = base64.b64decode(raw_content).decode("utf-8", errors="replace")
            lines = extract_copyright_lines(decoded)
            if lines:
                print(f"  Found copyright in {filename}", file=sys.stderr)
                return lines
        except Exception as exc:
            print(
                f"  Warning: could not decode {filename} for {owner}/{repo}: {exc}",
                file=sys.stderr,
            )
    return []


def get_dependency_info(identity: str, location: str, token: str | None) -> dict:
    """Fetch license and author information for a single dependency."""
    info: dict = {
        "name": identity,
        "url": location,
        "license_name": "Unknown",
        "authors": [],
        "license_text": None,
    }

    owner_repo = extract_github_owner_repo(location)
    if not owner_repo:
        print(f"  Skipping non-GitHub dependency: {identity}", file=sys.stderr)
        return info

    owner, repo = owner_repo
    print(f"  Fetching {owner}/{repo} ...", file=sys.stderr)

    license_data = github_request(f"/repos/{owner}/{repo}/license", token)

    if license_data:
        license_obj = license_data.get("license") or {}
        info["license_name"] = license_obj.get("name", "Unknown")

        raw_content = license_data.get("content", "")
        if raw_content:
            try:
                decoded = base64.b64decode(raw_content).decode("utf-8", errors="replace")
                info["license_text"] = decoded
                info["authors"] = extract_copyright_lines(decoded)
            except Exception as exc:
                print(f"  Warning: could not decode license for {identity}: {exc}", file=sys.stderr)

    # Apache 2.0 (and similar) projects keep their copyright in a NOTICE file
    # rather than in the license text itself — try that before falling back.
    if not info["authors"]:
        info["authors"] = fetch_notice_copyright(owner, repo, token)

    # Last resort: attribute to the repo owner.
    if not info["authors"]:
        info["authors"] = [f"Copyright {owner}"]

    return info


def format_entry(dep: dict) -> str:
    """Render one dependency as a Markdown section."""
    lines: list[str] = [
        f"## {dep['name']}",
        "",
        f"**Source:** <{dep['url']}>",
        "",
        f"**License:** {dep['license_name']}",
        "",
    ]

    if dep["authors"]:
        lines.append("**Copyright:**")
        lines.append("")
        for author in dep["authors"]:
            lines.append(f"- {author}")
        lines.append("")

    if dep["license_text"]:
        lines += [
            "<details>",
            "<summary>Full license text</summary>",
            "",
            "```",
            dep["license_text"].strip(),
            "```",
            "",
            "</details>",
            "",
        ]

    return "\n".join(lines)


def read_secret(key: str) -> str | None:
    """Return a value from SECRETS.json via plutil, or None if absent."""
    if not SECRETS_FILE.exists():
        return None
    result = subprocess.run(
        ["plutil", "-extract", key, "raw", "-o", "-", str(SECRETS_FILE)],
        capture_output=True,
        text=True,
    )
    value = result.stdout.strip()
    return value if result.returncode == 0 and value else None


def run_for_token(args: list[str], source: str) -> str | None:
    """Run a command that prints a token; return it, or None on failure."""
    try:
        result = subprocess.run(args, capture_output=True, text=True, check=True)
    except FileNotFoundError:
        print(f"Warning: {args[0]} not found.", file=sys.stderr)
        return None
    except subprocess.CalledProcessError as exc:
        print(f"Warning: {source} lookup failed: {exc.stderr.strip()}", file=sys.stderr)
        return None
    token = result.stdout.strip()
    if token:
        print(f"Obtained GitHub token from {source}.", file=sys.stderr)
        return token
    return None


def resolve_github_token() -> str | None:
    """Return a GitHub token from the environment, 1Password, or the gh CLI."""
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token

    op_ref = read_secret("github_token_op_ref")
    if op_ref:
        token = run_for_token(["op", "read", op_ref], "1Password")
        if token:
            return token

    return run_for_token(["gh", "auth", "token"], "gh CLI")


def main() -> None:
    token = resolve_github_token()
    if not token:
        print(
            "Warning: No GitHub token available. Unauthenticated requests are "
            "limited to 60/hr. Set GITHUB_TOKEN, add github_token_op_ref to "
            "SECRETS.json, or sign in with `gh auth login`.",
            file=sys.stderr,
        )

    if not RESOLVED_FILE.exists():
        print(f"Error: {RESOLVED_FILE} not found. Run `tuist install` first.", file=sys.stderr)
        sys.exit(1)

    resolved = json.loads(RESOLVED_FILE.read_text())
    pins: list[dict] = resolved.get("pins", [])
    print(f"Found {len(pins)} pinned dependencies.", file=sys.stderr)

    deps: list[dict] = []
    for pin in pins:
        identity: str = pin["identity"]
        location: str = pin["location"]
        print(f"Processing: {identity}", file=sys.stderr)
        deps.append(get_dependency_info(identity, location, token))
        # Stay well within GitHub's rate limits.
        time.sleep(0.5)

    deps.sort(key=lambda d: d["name"].lower())

    output_parts: list[str] = [
        "# Third-Party Licenses",
        "",
        "ScoreEdit uses the following open source libraries. "
        "Their licenses are reproduced below.",
        "",
        "---",
        "",
    ]

    for dep in deps:
        output_parts.append(format_entry(dep))
        output_parts.append("---")
        output_parts.append("")

    OUTPUT_FILE.write_text("\n".join(output_parts))
    print(f"Done. Written to {OUTPUT_FILE}", file=sys.stderr)


if __name__ == "__main__":
    main()

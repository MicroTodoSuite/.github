#!/usr/bin/env python3
"""Validate the MicroTodoSuite pull request delivery conventions."""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import PurePosixPath


ALLOWED_TYPES = ("feat", "fix", "test", "docs", "chore", "ci", "promote")
TYPE_PATTERN = "|".join(ALLOWED_TYPES)
TITLE_PATTERN = re.compile(
    rf"^(?P<type>{TYPE_PATTERN})"
    r"\((?P<scope>[a-z0-9]+(?:-[a-z0-9]+)*)\): (?P<summary>.+)$"
)
BRANCH_PATTERN = re.compile(
    rf"^(?:{TYPE_PATTERN})/[a-z0-9]+(?:-[a-z0-9]+)*$"
)
EXEMPT_BRANCH_PATTERNS = (
    re.compile(r"^dependabot/(?:[a-z0-9._-]+/)+[a-z0-9][a-z0-9._-]*$"),
    re.compile(
        r"^release-please--branches--[a-z0-9][a-z0-9-]*"
        r"(?:--components--[a-z0-9][a-z0-9-]*)?$"
    ),
    re.compile(r"^changesets-release/[a-z0-9]+(?:-[a-z0-9]+)*$"),
    re.compile(r"^semantic-release/[a-z0-9]+(?:-[a-z0-9]+)*$"),
)
NON_IMPERATIVE_WORDS = {
    "added",
    "adds",
    "adding",
    "changed",
    "changes",
    "changing",
    "documented",
    "documents",
    "documenting",
    "enforced",
    "enforces",
    "enforcing",
    "fixed",
    "fixes",
    "fixing",
    "implemented",
    "implements",
    "implementing",
    "removed",
    "removes",
    "removing",
    "updated",
    "updates",
    "updating",
}
REQUIRED_SECTIONS = (
    "What changes",
    "Why",
    "Tasks",
    "How it is verified",
    "Risk and rollback",
    "What this PR does not do",
)
SECTION_PATTERN = re.compile(r"^##[ \t]+(.+?)[ \t]*$", re.MULTILINE)
HTML_COMMENT_PATTERN = re.compile(r"<!--.*?-->", re.DOTALL)
INFRASTRUCTURE_CHECKBOX = (
    "Infrastructure changes: the documentation consulted through the required "
    "MCP servers is listed above"
)
KUBERNETES_PATH_PREFIXES = (
    "apps/",
    "bootstrap/",
    "charts/",
    "clusters/",
    "deploy/",
    "environments/",
    "helm/",
    "infrastructure/",
    "k8s/",
    "kubernetes/",
    "manifests/",
)


def validate_title(title: str) -> list[str]:
    match = TITLE_PATTERN.fullmatch(title)
    if match is None:
        return [
            "title must match <type>(<scope>): <summary> with an allowed type "
            f"({', '.join(ALLOWED_TYPES)})"
        ]

    summary = match.group("summary")
    errors: list[str] = []
    if summary != summary.lower():
        errors.append("title summary must be lower case")
    if summary.endswith("."):
        errors.append("title summary must not end with a period")
    if summary != summary.strip() or "\n" in summary or "\r" in summary:
        errors.append("title summary must be a single trimmed line")

    first_word_match = re.match(r"^[a-z]+", summary)
    first_word = first_word_match.group(0) if first_word_match else ""
    if not first_word or first_word in NON_IMPERATIVE_WORDS:
        errors.append("title summary must start with an imperative verb")
    return errors


def validate_branch(branch: str) -> list[str]:
    if BRANCH_PATTERN.fullmatch(branch):
        return []
    if any(pattern.fullmatch(branch) for pattern in EXEMPT_BRANCH_PATTERNS):
        return []
    return [
        "head branch must match <type>/<kebab-case-summary>; only explicit "
        "Dependabot and release-tool branches are exempt"
    ]


def body_sections(body: str) -> dict[str, str]:
    headings = list(SECTION_PATTERN.finditer(body))
    sections: dict[str, str] = {}
    for index, heading in enumerate(headings):
        start = heading.end()
        end = headings[index + 1].start() if index + 1 < len(headings) else len(body)
        sections.setdefault(heading.group(1), body[start:end])
    return sections


def validate_body(body: str) -> list[str]:
    sections = body_sections(body)
    errors: list[str] = []
    for required in REQUIRED_SECTIONS:
        if required not in sections:
            errors.append(f"missing required body section: {required}")
            continue
        substantive = HTML_COMMENT_PATTERN.sub("", sections[required]).strip()
        if not substantive:
            errors.append(f"body section contains no substantive content: {required}")
    return errors


def load_changed_files_from_file(path: str) -> list[str]:
    try:
        with open(path, encoding="utf-8") as changed_files:
            return [line.strip() for line in changed_files if line.strip()]
    except OSError as error:
        raise RuntimeError(f"cannot read changed files from {path}: {error}") from error


def load_changed_files_from_api() -> list[str]:
    token = os.environ.get("GH_TOKEN", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    pull_request = os.environ.get("PR_NUMBER", "")
    api_url = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")

    if not token or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise RuntimeError("GitHub API repository or token context is missing")
    if not pull_request.isdigit():
        raise RuntimeError("GitHub pull request number context is missing")

    encoded_repository = urllib.parse.quote(repository, safe="/")
    changed_files: list[str] = []
    page = 1
    while True:
        endpoint = (
            f"{api_url}/repos/{encoded_repository}/pulls/{pull_request}/files"
            f"?per_page=100&page={page}"
        )
        request = urllib.request.Request(
            endpoint,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {token}",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
        except (OSError, urllib.error.HTTPError, json.JSONDecodeError) as error:
            raise RuntimeError(f"cannot read pull request files: {error}") from error

        if not isinstance(payload, list):
            raise RuntimeError("GitHub pull request files response is not a list")
        filenames = [
            item.get("filename", "")
            for item in payload
            if isinstance(item, dict) and item.get("filename")
        ]
        changed_files.extend(filenames)
        if len(payload) < 100:
            break
        page += 1
    return changed_files


def load_changed_files() -> list[str]:
    fixture_path = os.environ.get("CHANGED_FILES_FILE", "")
    if fixture_path:
        return load_changed_files_from_file(fixture_path)
    return load_changed_files_from_api()


def is_kubernetes_manifest(path: str) -> bool:
    normalized = path.lstrip("./")
    suffix = PurePosixPath(normalized).suffix.lower()
    return suffix in {".yaml", ".yml"} and normalized.startswith(
        KUBERNETES_PATH_PREFIXES
    )


def touches_infrastructure(changed_files: list[str]) -> bool:
    for path in changed_files:
        suffix = PurePosixPath(path).suffix.lower()
        if suffix in {".tf", ".tfvars"} or is_kubernetes_manifest(path):
            return True
    return False


def infrastructure_checkbox_checked(body: str) -> bool:
    pattern = re.compile(
        rf"^[ \t]*-[ \t]*\[[xX]\][ \t]+{re.escape(INFRASTRUCTURE_CHECKBOX)}"
        r"[ \t]*$",
        re.MULTILINE,
    )
    return pattern.search(body) is not None


def validate_infrastructure(body: str, infrastructure: str) -> list[str]:
    if infrastructure not in {"true", "false"}:
        return ["infrastructure input must be true or false"]
    if infrastructure == "false":
        return []

    try:
        changed_files = load_changed_files()
    except RuntimeError as error:
        return [str(error)]
    if touches_infrastructure(changed_files) and not infrastructure_checkbox_checked(body):
        return [
            "infrastructure documentation checkbox must be checked when Terraform, "
            "tfvars, or Kubernetes manifests change"
        ]
    return []


def main() -> int:
    title = os.environ.get("PR_TITLE", "")
    branch = os.environ.get("PR_HEAD_BRANCH", "")
    body = os.environ.get("PR_BODY", "")
    infrastructure = os.environ.get("INFRASTRUCTURE", "false").lower()

    errors = [
        *validate_title(title),
        *validate_branch(branch),
        *validate_body(body),
        *validate_infrastructure(body, infrastructure),
    ]
    if errors:
        for error in errors:
            print(f"conventions: ERROR: {error}", file=sys.stderr)
        return 1

    print("conventions: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

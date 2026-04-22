#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path
from urllib.parse import quote
from xml.etree import ElementTree as ET


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z.-]+))?"
    r"(?:\+[0-9A-Za-z.-]+)?$"
)
ALLOWED_PRERELEASE_LABELS = {"alpha", "beta", "rc"}


class ReleaseAppcastError(Exception):
    pass


def is_prerelease(version: str) -> bool:
    match = SEMVER_RE.fullmatch(version)
    if not match:
        raise ReleaseAppcastError(f"Invalid SemVer version: {version}")

    prerelease = match.group("prerelease")
    if not prerelease:
        return False

    label = prerelease.split(".", 1)[0].lower()
    if label not in ALLOWED_PRERELEASE_LABELS:
        allowed = ", ".join(sorted(ALLOWED_PRERELEASE_LABELS))
        raise ReleaseAppcastError(f"Unsupported prerelease label '{label}' in {version}; expected one of: {allowed}")
    return True


def load_asset_tags(path: Path) -> dict[str, str]:
    tags: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        parts = line.split("\t", 1)
        if len(parts) != 2 or not parts[0] or not parts[1]:
            raise ReleaseAppcastError(f"Invalid asset tag mapping on line {line_number}: {line}")
        if parts[0] in tags and tags[parts[0]] != parts[1]:
            raise ReleaseAppcastError(f"Asset {parts[0]} is mapped to multiple release tags")
        tags[parts[0]] = parts[1]
    return tags


def release_asset_url(repo: str, tag: str, filename: str) -> str:
    return f"https://github.com/{repo}/releases/download/{quote(tag, safe='')}/{quote(filename, safe='')}"


def local_name(name: str) -> str:
    if name.startswith("{"):
        return name.rsplit("}", 1)[-1]
    return name


def assert_no_deltas(root: ET.Element) -> None:
    for element in root.iter():
        if "delta" in local_name(element.tag).lower():
            raise ReleaseAppcastError("Generated appcast contains Sparkle delta entries")
        for attribute in element.attrib:
            if "delta" in local_name(attribute).lower():
                raise ReleaseAppcastError("Generated appcast contains Sparkle delta attributes")


def assert_no_placeholder_urls(root: ET.Element) -> None:
    for enclosure in root.iter("enclosure"):
        url = enclosure.get("url", "")
        if "__placeholder__" in url:
            raise ReleaseAppcastError(f"Appcast enclosure URL was not rewritten: {url}")


def rewrite_channel(item: ET.Element, prerelease: bool) -> None:
    channel_tag = f"{{{SPARKLE_NS}}}channel"
    channel = item.find(channel_tag)
    if prerelease:
        if channel is None:
            channel = ET.SubElement(item, channel_tag)
        channel.text = "beta"
        return

    for child in list(item):
        if child.tag == channel_tag:
            item.remove(child)


def postprocess_appcast(appcast_path: Path, repo: str, asset_tags: dict[str, str]) -> None:
    ET.register_namespace("sparkle", SPARKLE_NS)
    tree = ET.parse(appcast_path)
    root = tree.getroot()

    items = list(root.iter("item"))
    if not items:
        raise ReleaseAppcastError("Generated appcast does not contain any items")

    for item in items:
        short_version = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
        if short_version is None or not short_version.text or not short_version.text.strip():
            raise ReleaseAppcastError("Appcast item is missing sparkle:shortVersionString")

        version = short_version.text.strip()
        rewrite_channel(item, is_prerelease(version))

        enclosure = item.find("enclosure")
        if enclosure is None:
            raise ReleaseAppcastError(f"Appcast item {version} is missing an enclosure")

        filename = enclosure.get("url", "").rsplit("/", 1)[-1]
        if not filename:
            raise ReleaseAppcastError(f"Appcast item {version} has an enclosure without a filename")
        if filename not in asset_tags:
            raise ReleaseAppcastError(f"No release tag mapping found for appcast asset: {filename}")

        enclosure.set("url", release_asset_url(repo, asset_tags[filename], filename))

    assert_no_deltas(root)
    assert_no_placeholder_urls(root)
    tree.write(appcast_path, xml_declaration=True, encoding="utf-8")


def classify_version(args: argparse.Namespace) -> None:
    prerelease = is_prerelease(args.version)
    output = f"prerelease={'true' if prerelease else 'false'}\n"
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as f:
            f.write(output)
    else:
        sys.stdout.write(output)


def postprocess(args: argparse.Namespace) -> None:
    postprocess_appcast(
        appcast_path=Path(args.appcast),
        repo=args.repo,
        asset_tags=load_asset_tags(Path(args.asset_tags)),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Release appcast helpers")
    subparsers = parser.add_subparsers(required=True)

    classify = subparsers.add_parser("classify-version")
    classify.add_argument("version")
    classify.add_argument("--github-output")
    classify.set_defaults(func=classify_version)

    postprocess_parser = subparsers.add_parser("postprocess")
    postprocess_parser.add_argument("--appcast", required=True)
    postprocess_parser.add_argument("--repo", required=True)
    postprocess_parser.add_argument("--asset-tags", required=True)
    postprocess_parser.set_defaults(func=postprocess)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.func(args)
    except ReleaseAppcastError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

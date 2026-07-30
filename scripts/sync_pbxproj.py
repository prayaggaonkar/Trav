#!/usr/bin/env python3
"""Register/unregister Swift sources in Trav.xcodeproj.

The project uses classic (non file-system-synchronized) groups, so new sources
need explicit PBXFileReference / PBXBuildFile / group / Sources entries. Editing
those four places by hand is error-prone, hence this script.

Usage:
    python3 scripts/sync_pbxproj.py add  <group-name> <File.swift> [...]
    python3 scripts/sync_pbxproj.py drop <File.swift> [...]
"""

import hashlib
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent / "Trav.xcodeproj" / "project.pbxproj"


def uid(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def group_block(text: str, name: str) -> re.Match:
    pattern = re.compile(
        r"(\t\t[0-9A-Z]{24} /\* " + re.escape(name) + r" \*/ = \{\n"
        r"\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)((?:\t\t\t\t.*\n)*?)(\t\t\t\);\n"
        r"\t\t\tpath = " + re.escape(name) + r";)"
    )
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"group {name!r} not found")
    return match


def add(text: str, group: str, filenames: list[str]) -> str:
    file_refs = []
    build_files = []
    children = []
    sources = []

    for name in filenames:
        if f"/* {name} */" in text:
            print(f"skip {name}: already registered")
            continue
        ref = uid(f"ref:{group}:{name}")
        build = uid(f"build:{group}:{name}")
        file_refs.append(
            f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; "
            f'sourceTree = "<group>"; }};\n'
        )
        build_files.append(
            f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {ref} /* {name} */; }};\n"
        )
        children.append(f"\t\t\t\t{ref} /* {name} */,\n")
        sources.append(f"\t\t\t\t{build} /* {name} in Sources */,\n")

    if not file_refs:
        return text

    text = text.replace(
        "/* End PBXBuildFile section */", "".join(build_files) + "/* End PBXBuildFile section */", 1
    )
    text = text.replace(
        "/* End PBXFileReference section */",
        "".join(file_refs) + "/* End PBXFileReference section */",
        1,
    )

    match = group_block(text, group)
    text = text[: match.end(2)] + "".join(children) + text[match.end(2) :]

    marker = "/* Sources */ = {"
    idx = text.index(marker)
    files_idx = text.index("files = (\n", idx) + len("files = (\n")
    text = text[:files_idx] + "".join(sources) + text[files_idx:]
    return text


def drop(text: str, filenames: list[str]) -> str:
    for name in filenames:
        kept = [
            line
            for line in text.splitlines(keepends=True)
            if f"/* {name} */" not in line and f"/* {name} in Sources */" not in line
        ]
        text = "".join(kept)
    return text


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)

    text = PROJECT.read_text()
    command = sys.argv[1]

    if command == "add":
        text = add(text, sys.argv[2], sys.argv[3:])
    elif command == "drop":
        text = drop(text, sys.argv[2:])
    else:
        raise SystemExit(__doc__)

    PROJECT.write_text(text)
    print(f"updated {PROJECT}")


if __name__ == "__main__":
    main()

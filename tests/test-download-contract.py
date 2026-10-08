"""Developer/CI only: validate the actual pinned download, never install an app."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
METADATA = ROOT / "resources/download-snapshot.json"
COMMANDS = ["macOS-一键安装.command", "macOS-兼容汉化.command", "macOS-检查状态.command",
            "macOS-打开中文版.command", "macOS-恢复英文.command"]
RUNTIME = ["scripts/check-macos-package.sh", "scripts/install_macos.sh", "scripts/macos-copy.sh",
           "scripts/inspect-macos-asar.js", "scripts/macos-integrity.js", "scripts/check-macos-copy-paths.js",
           "scripts/macos-local.entitlements.plist", "resources/macos-package-files.txt"]


def validate(data, meta):
    commit = meta["commit"]
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("must download an immutable commit, never main or a tag")
    expected_url = f"https://codeload.github.com/ymh3753201/codex-zh-CN/zip/{commit}"
    if meta["url"] != expected_url:
        raise ValueError("wrong download endpoint")
    if hashlib.sha256(data).hexdigest() != meta["archiveSha256"]:
        raise ValueError("source archive SHA-256 does not match; stop before installation")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        prefix = f"codex-zh-CN-{commit}/"
        names = archive.namelist()
        for name in names:
            if not name.startswith(prefix) or ".." in PurePosixPath(name).parts or "\\" in name:
                raise ValueError("archive contains an unsafe path")
        if len(set(names)) != len(names):
            raise ValueError("archive contains duplicate paths")
        if prefix + "docs/学员通用AI下载与汉化提示词.md" in names:
            raise ValueError("tool archive contains an old maintenance download prompt")

        def read(relative):
            try:
                return archive.read(prefix + relative)
            except KeyError as exc:
                raise ValueError(f"wrong or incomplete tool download: missing {relative}") from exc

        for relative in COMMANDS + RUNTIME + ["scripts/install_windows.ps1", "resources/release.json"]:
            read(relative)
        mac_version = json.loads(read("resources/macos-release.json"))["release"]
        windows_version = json.loads(read("resources/release.json"))["release"]
        if mac_version != meta["macOSToolVersion"] or windows_version != meta["windowsToolVersion"]:
            raise ValueError("downloaded tool versions do not match the announced snapshot")
        installer = read("scripts/install_macos.sh").decode("utf-8")
        if f'TOOL_VERSION="{mac_version}"' not in installer:
            raise ValueError("mixed macOS installer and version record")
        for relative in read("resources/macos-package-files.txt").decode("utf-8").splitlines():
            if not relative or PurePosixPath(relative).is_absolute() or ".." in PurePosixPath(relative).parts:
                raise ValueError("unsafe package manifest")
            read(relative)
        readme = read("README.md").decode("utf-8")
        for excluded in ("docs/学员通用AI下载与汉化提示词.md", "docs/下载版本与平台入口.md"):
            if f"]({excluded})" in readme:
                raise ValueError("tool README links to an excluded maintenance file")
    return mac_version, windows_version


def regressions(meta):
    # The old Windows-only package has a matching checksum but still must fail.
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        prefix = f"codex-zh-CN-{meta['commit']}/"
        archive.writestr(prefix + "scripts/install_windows.ps1", "# Windows-only fixture")
        archive.writestr(prefix + "resources/release.json", '{"release":"0.3.4"}')
    old = stream.getvalue()
    try:
        validate(old, {**meta, "archiveSha256": hashlib.sha256(old).hexdigest()})
    except ValueError as exc:
        assert "missing macOS-" in str(exc), str(exc)
    else:
        raise AssertionError("a verified checksum must not imply macOS support")
    try:
        validate(old, {**meta, "commit": "main"})
    except ValueError as exc:
        assert "immutable" in str(exc), str(exc)
    else:
        raise AssertionError("main must never replace the pinned snapshot")


def main():
    meta = json.loads(METADATA.read_text(encoding="utf-8"))
    regressions(meta)
    if len(sys.argv) == 3 and sys.argv[1] == "--archive":
        data = Path(sys.argv[2]).read_bytes()
    elif len(sys.argv) == 1:
        request = urllib.request.Request(meta["url"], headers={"User-Agent": "codex-zh-CN-download-test"})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read(16 * 1024 * 1024 + 1)
        if len(data) > 16 * 1024 * 1024:
            raise ValueError("unexpectedly large source archive")
    else:
        raise ValueError("usage: test-download-contract.py [--archive source.zip]")
    mac, windows = validate(data, meta)
    # Wrong published checksum must fail as well as a structurally wrong package.
    try:
        validate(data, {**meta, "archiveSha256": "0" * 64})
    except ValueError as exc:
        assert "SHA-256" in str(exc), str(exc)
    else:
        raise AssertionError("bad checksum was accepted")
    prompt = (ROOT / "docs/学员通用AI下载与汉化提示词.md").read_text(encoding="utf-8")
    download_doc = (ROOT / "docs/下载版本与平台入口.md").read_text(encoding="utf-8")
    for content in (prompt, download_doc):
        for expected in (meta["url"], meta["archiveSha256"], meta["commit"]):
            assert expected in content, f"learner instructions diverged: {expected}"
    print(f"[PASS] actual snapshot {meta['commit']}: source ZIP SHA-256 and Windows {windows}/macOS {mac} entries")
    print("[PASS] old Windows-only ZIP, substituted main and wrong checksum all rejected before installation")


if __name__ == "__main__":
    main()

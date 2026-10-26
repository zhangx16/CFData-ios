#!/usr/bin/env python3
"""Generate an importable copy of the upstream executable; never edit upstream files."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/mobile"
CORE = OUT / "internal/core"


def replace_once(text, old, new, filename):
    if text.count(old) != 1:
        raise RuntimeError(f"Upstream changed: expected one {old!r} in {filename}")
    return text.replace(old, new, 1)


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    CORE.mkdir(parents=True)
    upstream = ROOT / "combined_refactor"
    for source in upstream.iterdir():
        if source.suffix == ".go" and not source.name.endswith("_test.go"):
            text = replace_once(source.read_text(), "package main", "package core", source.name)
            if source.name == "cli.go":
                text = replace_once(text,
                    'func defaultCLIConfigPath() string {\n\texe, err := os.Executable()',
                    'func defaultCLIConfigPath() string {\n\treturn mobileConfigPath()\n}\n\nfunc unusedDesktopConfigPath() string {\n\texe, err := os.Executable()', source.name)
            if source.name == "server.go":
                text = replace_once(text, 'session := &appSession{ws: ws}',
                    'session := &appSession{ws: ws}\n\tmobileTrackSession(session)\n\tdefer mobileUntrackSession(session)', source.name)
                text = replace_once(text, 'handler, ok := handlers[request.Type]',
                    'if !mobileAllowRequest(session, request.Type) {\n\t\t\tcontinue\n\t\t}\n\t\thandler, ok := handlers[request.Type]', source.name)
            if source.name == "session.go":
                text = replace_once(text,
                    'func (s *appSession) beginTask(cancel context.CancelFunc, label string, mode string, params map[string]interface{}) bool {',
                    'func (s *appSession) beginTask(cancel context.CancelFunc, label string, mode string, params map[string]interface{}) bool {\n\tmobileState.Lock()\n\tdefer mobileState.Unlock()\n\tif mobileState.paused { return false }', source.name)
            (CORE / source.name).write_text(text)
        elif source.name in ("index.html", "login.html", "favicon.png", "ca-certificates.crt"):
            shutil.copy2(source, CORE / source.name)
    for name in ("go.mod", "go.sum"):
        text = (upstream / name).read_text()
        if name == "go.mod":
            text = replace_once(text, "module cfdata", "module cfdataios", name)
        (OUT / name).write_text(text)
    shutil.copy2(ROOT / "ios/mobile/core.go", CORE / "mobile.go")
    shutil.copy2(ROOT / "ios/mobile/core_test.go", CORE / "mobile_test.go")
    (OUT / "mobile").mkdir()
    shutil.copy2(ROOT / "ios/mobile/mobile.go", OUT / "mobile/mobile.go")
    resources = ROOT / "ios/Resources"
    resources.mkdir(exist_ok=True)
    shutil.copy2(ROOT / "LICENSE", resources / "LICENSE.txt")
    print(f"Prepared mobile Go module: {OUT}")


if __name__ == "__main__":
    main()

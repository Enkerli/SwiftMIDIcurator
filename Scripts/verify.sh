#!/bin/bash
#
# Checks the parts of SwiftMIDIcurator that Xcode's test targets can't reach.
#
#   Scripts/verify.sh          # all suites
#   Scripts/verify.sh curate   # one suite
#
# Suites:
#   identity — the audio component triple and the bundle identifier are unique
#              across every sibling checkout, JUCE and Swift alike, and match
#              the host app's lookup. First, because both are forever and this
#              project was scaffolded from another one's.
#   curate   — what the plug-in decides: how a file becomes a clip, what counts
#              as the same clip twice, and what order the queue is in. The
#              scheduling half is C++ and lives in the foundation package's own
#              Scripts/check-kernel.sh, which this runs too, because a green
#              here with a broken kernel would be a lie by omission.
#   kernel   — that, run from the foundation package.
#   gaps     — the gaps register, likewise. This plug-in has to have a section
#              in it or the check fails.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$REPO/SwiftMIDIcuratorExtension"
PACKAGE="${ENKERLI_SWIFT:-$REPO/../enkerli-swift}"
MUSIC_SUITE="${MUSIC_SUITE:-$REPO/../music-suite}"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

which="${1:-all}"
status=0

PKG_BIN=""
build_package() {
    [ -n "$PKG_BIN" ] && return 0
    if [ ! -f "$PACKAGE/Package.swift" ]; then
        echo "FAIL: no foundation package at $PACKAGE"
        echo "      git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift"
        echo "      (or set ENKERLI_SWIFT=/path/to/enkerli-swift)"
        status=1
        return 1
    fi
    swift build --package-path "$PACKAGE" >/dev/null || {
        echo "FAIL: the foundation package did not build"; status=1; return 1; }
    PKG_BIN="$(swift build --package-path "$PACKAGE" --show-bin-path)"
}

# UI is left out — these suites are headless — and so are the package's own test
# targets, whose objects carry a second `main`.
#
# Shell is linked, because the library and the session are what this plug-in is,
# and dropping it would mean the suite could not see them. That drags in
# `Kernel`, a C++ target with no .swiftmodule — just a module map SwiftPM
# generates beside its objects — so Swift has to be pointed at that and told to
# speak C++.
package_flags() {
    build_package || return 1
    echo "-I $PKG_BIN/Modules"
    echo "-Xcc -fmodule-map-file=$PKG_BIN/Kernel.build/module.modulemap"
    echo "-Xcc -I$PACKAGE/Sources/Kernel/include"
    echo "-cxx-interoperability-mode=default"
    find "$PKG_BIN" -name "*.o" ! -path "*/UI.build/*" ! -path "*Tests.build/*" | sort
}

# Every extension source that does not need the AU shell: the session and what
# it derives. The two AU subclasses and the view need CoreAudioKit and a host,
# and are checked by building the schemes.
headless_sources() {
    find "$EXT/Library" -name "*.swift" 2>/dev/null | sort
}

run_identity() {
    echo "── identity ───────────────────────────────────────"
    python3 "$REPO/Scripts/tests/component-identity.py" || status=1
}

run_curate() {
    echo "── curate ─────────────────────────────────────────"
    cp "$REPO/Scripts/tests/curate-main.swift" "$BUILD/main.swift"
    swiftc -Onone $(package_flags) $(headless_sources) "$BUILD/main.swift" \
        -o "$BUILD/curate" || { status=1; return 0; }
    "$BUILD/curate" || status=1
}

# The gaps register, from the package that holds it. A plug-in whose gaps are
# not written down has them anyway, and this repo is exactly the kind that would
# acquire some quietly: it was built in an afternoon.
run_gaps() {
    echo "── gaps (from the foundation package) ─────────────"
    if [ ! -x "$PACKAGE/Scripts/check-gaps.sh" ]; then
        echo "FAIL: no gaps check at $PACKAGE/Scripts/check-gaps.sh"
        status=1
        return 0
    fi
    "$PACKAGE/Scripts/check-gaps.sh" || status=1
}

run_kernel() {
    echo "── kernel (from the foundation package) ───────────"
    if [ ! -x "$PACKAGE/Scripts/check-kernel.sh" ]; then
        echo "FAIL: no kernel check at $PACKAGE/Scripts/check-kernel.sh"
        status=1
        return 0
    fi
    "$PACKAGE/Scripts/check-kernel.sh" || status=1
}

case "$which" in
    identity) run_identity ;;
    curate) run_curate ;;
    kernel) run_kernel ;;
    gaps) run_gaps ;;
    all) run_identity; run_curate; run_kernel; run_gaps ;;
    *) echo "unknown suite: $which"; exit 2 ;;
esac

echo
if [ $status -eq 0 ]; then echo "verify: OK"; else echo "verify: FAILURES"; fi
exit $status

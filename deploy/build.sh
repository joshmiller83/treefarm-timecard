#!/bin/bash
# Build the server in release mode and stage it in $DATA_DIR/bin. No sudo.
# The swap is atomic, so a running server keeps its old binary until it restarts.
source "$(dirname "$0")/lib.sh"

[[ $EUID -ne 0 ]] || die "run without sudo"

say "Testing the server first"
swift test --package-path "$REPO_DIR/Server" >/dev/null || die "server tests failed; not deploying"

say "Building $SERVER_PRODUCT (release)"
swift build -c release --package-path "$REPO_DIR/Server" --product "$SERVER_PRODUCT"
built="$(swift build -c release --package-path "$REPO_DIR/Server" --show-bin-path)/$SERVER_PRODUCT"
[[ -x "$built" ]] || die "no binary at $built"

install -d "$DATA_DIR"/{bin,data,backups,logs}
cp "$built" "$BIN.new"
mv -f "$BIN.new" "$BIN"
git -C "$REPO_DIR" describe --always --dirty > "$DATA_DIR/bin/VERSION"
say "Staged $BIN ($(cat "$DATA_DIR/bin/VERSION"))"

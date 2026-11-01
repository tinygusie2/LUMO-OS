#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${LUMO_TEST_DISPOSABLE_SESSION:-} != 1 ]]; then
    printf 'Use only in a disposable VM: this test removes and reinstalls galculator and GNOME Calculator. Set LUMO_TEST_DISPOSABLE_SESSION=1.\n' >&2
    exit 1
fi
if pgrep -x lumo-store >/dev/null; then
    printf 'Close Store before running the installation test.\n' >&2
    exit 1
fi
log=${LUMO_INSTALL_TEST_LOG:-$(mktemp /tmp/lumo-install-test.XXXXXX)}
set +e
LUMO_QML_STORE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)" \
    timeout 1900 lumo-store > "$log" 2>&1
result=$?
set -e
cat "$log"
printf 'Installation log: %s\n' "$log"
[[ $result == 0 ]]
grep -Fq STORE_INSTALL_OK "$log"

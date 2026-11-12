#!/usr/bin/env bash
# Return a Sony BRAVIA VU3 to stock Google TV Home and built-in TV features.
#
# Usage:
#   TV_HOST=<TV IP> tools/restore-stock-vu3.sh
#   TV_HOST=127.0.0.1 TV_PORT=5555 tools/restore-stock-vu3.sh  # through tools/relay.py
#
# ADB must be enabled and reachable while this runs. It restores the Sony package list with
# tools/restore.sh, removes the theme overlay, enables stock Live TV and Ambient, selects Ambient
# as the stock screensaver, then disables (does not uninstall) CleanYourTV, Tatami, Remote Access and
# the PS5 input tile.
# Streaming apps and user data are left installed. ADB is left in whatever state it had at start.
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "usage: TV_HOST=<TV IP> tools/restore-stock-vu3.sh" >&2
  exit 2
fi
if [ -z "${TV_HOST:-}" ]; then
  echo "Set TV_HOST to the TV's IP, or 127.0.0.1 when using tools/relay.py." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export TV_HOST
if [ -n "${TV_PORT:-}" ]; then
  export TV_PORT
else
  unset TV_PORT
fi
PY=tools/venv/bin/python
[ -x "$PY" ] || PY=tools/venv/Scripts/python.exe
[ -x "$PY" ] || {
  echo "Run: python3 -m venv tools/venv && tools/venv/bin/pip install -r tools/requirements.txt" >&2
  exit 1
}

tv() { "$PY" -I tools/tv.py "$@"; }
assert_enabled() {
  local packages
  packages="$(tv 'pm list packages -e --user 0' | tr -d '\r')"
  printf '%s\n' "$packages" | grep -Fx "package:$1" >/dev/null || {
    echo "$1 is not enabled on the TV." >&2
    return 1
  }
}
assert_disabled() {
  local packages
  packages="$(tv 'pm list packages -d --user 0' | tr -d '\r')"
  printf '%s\n' "$packages" | grep -Fx "package:$1" >/dev/null || {
    echo "$1 is not disabled on the TV." >&2
    return 1
  }
}

DEVICE="$(tv 'getprop ro.product.device' | tr -d '\r[:space:]')"
case "$DEVICE" in
  BRAVIA_VU3|BRAVIA_VU3_4K) ;;
  *) echo "This script is for Sony BRAVIA VU3; the connected device identifies as '$DEVICE'. Nothing was changed." >&2; exit 1 ;;
esac

# Remove the custom overlay while its launcher and input helper can still restart normally.
tools/theme.sh --reset

# Restore the saved package states and return Home to Sony's stock Google TV launcher.
tools/restore.sh \
  examples/sony-bravia-vu3/debloat.txt com.google.android.apps.tv.launcherx

# Explicitly select the stock launcher even if an old recovery record predates launcher state capture.
tv 'pm enable --user 0 com.google.android.apps.tv.launcherx' >/dev/null
STOCK_HOME="$(tv 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME com.google.android.apps.tv.launcherx' | tr -d '\r' | tail -n 1)"
case "$STOCK_HOME" in
  com.google.android.apps.tv.launcherx/*) ;;
  *) echo "Could not resolve Sony's stock Home activity ('$STOCK_HOME'); CleanYourTV was left installed." >&2; exit 1 ;;
esac
tv "cmd package set-home-activity --user 0 $STOCK_HOME" >/dev/null
HOME_NOW="$(tv 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME' | tr -d '\r' | tail -n 1)"
case "$HOME_NOW" in
  com.google.android.apps.tv.launcherx/*) ;;
  *) echo "Stock Home did not take (the TV resolves '$HOME_NOW'); CleanYourTV was left installed." >&2; exit 1 ;;
esac

# Restore built-in TV and Ambient screensaver services. Tatami remains installed but is not selected.
tv 'pm enable --user 0 com.android.tv' >/dev/null
tv 'pm enable --user 0 com.google.android.apps.tv.dreamx' >/dev/null
assert_enabled com.android.tv
assert_enabled com.google.android.apps.tv.dreamx
tv 'settings put secure screensaver_components com.google.android.apps.tv.dreamx/.service.Backdrop' >/dev/null
tv 'settings put secure screensaver_default_component com.google.android.apps.tv.dreamx/.service.Backdrop' >/dev/null
tv 'settings put secure screensaver_enabled 1' >/dev/null
tv 'settings put secure screensaver_activate_on_sleep 1' >/dev/null
tv 'settings put secure screensaver_activate_on_dock 1' >/dev/null

# Remove only this launcher's key helper from Accessibility, preserving any other enabled services.
SERVICES="$(tv 'settings get secure enabled_accessibility_services' | tr -d '\r')"
NEW_SERVICES="$(printf '%s' "$SERVICES" | "$PY" -I -c 'import sys; s=sys.stdin.read().strip(); print(":".join(x for x in s.split(":") if x and x != "com.gathin.tvhome/.InputKeyService" and x != "null"), end="")')"
tv "settings put secure enabled_accessibility_services '$NEW_SERVICES'" >/dev/null
SERVICES_NOW="$(tv 'settings get secure enabled_accessibility_services' | tr -d '\r')"
case ":$SERVICES_NOW:" in
  *:com.gathin.tvhome/.InputKeyService:*) echo "CleanYourTV's key helper is still enabled in Accessibility." >&2; exit 1 ;;
esac

# Disable optional apps and the custom Home only after the stock Home has been set and confirmed.
# Each package stays installed and can be re-enabled in Android Settings or with pm enable.
tv 'pm disable-user --user 0 io.github.pbanddev.tatami' >/dev/null
tv 'pm disable-user --user 0 io.github.maxhayim.remoteaccess' >/dev/null
tv 'pm disable-user --user 0 com.clean.ps5' >/dev/null
tv 'pm disable-user --user 0 com.gathin.tvhome' >/dev/null
assert_disabled io.github.pbanddev.tatami
assert_disabled io.github.maxhayim.remoteaccess
assert_disabled com.clean.ps5
assert_disabled com.gathin.tvhome
tv 'am start -a android.intent.action.MAIN -c android.intent.category.HOME' >/dev/null

HOME_FINAL="$(tv 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME' | tr -d '\r' | tail -n 1)"
SCREENSAVER_FINAL="$(tv 'settings get secure screensaver_default_component' | tr -d '\r')"
SCREENSAVER_ENABLED="$(tv 'settings get secure screensaver_enabled' | tr -d '\r')"
case "$HOME_FINAL" in
  com.google.android.apps.tv.launcherx/*) ;;
  *) echo "Final Home check failed ('$HOME_FINAL'). Re-enable com.gathin.tvhome if needed, then check Home in Settings." >&2; exit 1 ;;
esac
[ "$SCREENSAVER_FINAL" = 'com.google.android.apps.tv.dreamx/.service.Backdrop' ] || {
  echo "Stock Home is active, but the screensaver selection did not verify ('$SCREENSAVER_FINAL')." >&2
  exit 1
}
[ "$SCREENSAVER_ENABLED" = '1' ] || {
  echo "Stock Home is active, but the screensaver is not enabled (screensaver_enabled=$SCREENSAVER_ENABLED)." >&2
  exit 1
}

echo "Stock Google TV Home is active. Live TV and Google TV Ambient are enabled."
echo "Tatami, Remote Access, the PS5 input tile and CleanYourTV are disabled but remain installed. ADB was not changed."

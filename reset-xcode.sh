#!/bin/bash
# reset-xcode.sh — unstick Xcode + iOS Simulator when the app hangs on a spinner.
#
# What it does (in order):
#   1. Quits Xcode (kills the lldb/debugserver session holding a frozen app)
#   2. Force-kills any leftover debugserver / lldb / Food App processes
#   3. Shuts down all booted simulators + restarts the CoreSimulator service
#   4. Wipes DerivedData (the stale-binary cause)
#   5. Re-boots your usual simulator and (optionally) removes the old app install
#
# It does NOT "Erase All Content" — your simulator keychain / sign-in session
# survives, so you won't re-hit the "Connecting…" sign-in hang.
#
# Usage:
#   ./reset-xcode.sh            # normal reset (keeps simulator data + session)
#   ./reset-xcode.sh --nuke     # ALSO erases the simulator (wipes sign-in too)
#
# After it finishes: reopen Xcode → Clean Build Folder is unnecessary (DerivedData
# is already gone) → just press Run. If Run-under-debugger ever wedges again,
# launch by TAPPING THE APP ICON on the simulator instead of Cmd+R.

set -u
SIM_UDID="A8DF8066-1B4F-4E0C-AD84-148529CEE8BA"   # iPhone 17 Pro (iOS 26.4)
BUNDLE_ID="com.shantanu.foodapp"
NUKE=0
[ "${1:-}" = "--nuke" ] && NUKE=1

echo "==> 1/5  Quitting Xcode…"
osascript -e 'tell application "Xcode" to quit' 2>/dev/null
sleep 2
# If it refused (modal dialog etc.), force it.
pkill -9 -x Xcode 2>/dev/null && echo "    (force-quit Xcode)"

echo "==> 2/5  Killing frozen debug processes (debugserver / lldb / app)…"
for name in debugserver lldb-rpc-server lldb "Food App"; do
  pids=$(pgrep -f "$name" 2>/dev/null)
  if [ -n "$pids" ]; then
    echo "    killing $name: $pids"
    kill -9 $pids 2>/dev/null
  fi
done

echo "==> 3/5  Shutting down simulators + restarting CoreSimulator service…"
xcrun simctl shutdown all 2>/dev/null
# Bounce the CoreSimulator daemon — clears a wedged service that ignores simctl.
killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null && echo "    (restarted CoreSimulatorService)"
sleep 2

echo "==> 4/5  Wiping DerivedData…"
rm -rf ~/Library/Developer/Xcode/DerivedData
echo "    DerivedData removed."

echo "==> 5/5  Re-booting simulator $SIM_UDID…"
if [ "$NUKE" = "1" ]; then
  echo "    --nuke: ERASING simulator (this wipes the sign-in session)…"
  xcrun simctl erase "$SIM_UDID" 2>/dev/null
fi
xcrun simctl boot "$SIM_UDID" 2>/dev/null
xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null | tail -1
# Remove the stale app install so the next Run deploys a clean copy.
# (Skipped after --nuke since the erase already removed it.)
if [ "$NUKE" = "0" ]; then
  xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null && echo "    Removed old app install (session preserved)."
fi
open -a Simulator 2>/dev/null

echo ""
echo "==> DONE. Now: open Xcode → press Run (Cmd+R)."
echo "    If it STILL hangs white under the debugger, tap the app ICON on the"
echo "    simulator home screen instead — that launches without lldb."

#!/usr/bin/env bash
#
# One simulator per worktree.
#
# Parallel Claude sessions each drive their own branch, and the simulator tools
# default to "whatever is booted", so without this they install over each
# other's build and screenshot each other's screen. The device is named after
# the worktree directory, which is unique per branch.
#
#   scripts/ios-simulator.sh          boot (creating it the first time), print the name
#   scripts/ios-simulator.sh --udid   print just the UDID, for simctl commands
#   scripts/ios-simulator.sh --delete remove this worktree's simulator
#
# Override the hardware or the iOS version, e.g.
#   SIM_DEVICE_TYPE="iPhone 17 Pro Max" scripts/ios-simulator.sh
#   SIM_RUNTIME="iOS 26.3" scripts/ios-simulator.sh
#
# The default runtime is the newest one installed, which can be ahead of what
# users actually run. Pin SIM_RUNTIME when a behaviour has to be checked on the
# version that ships.

set -euo pipefail

DEVICE_TYPE="${SIM_DEVICE_TYPE:-iPhone 17 Pro}"
RUNTIME="${SIM_RUNTIME:-}"
WORKTREE="$(basename "$(git rev-parse --show-toplevel)")"
NAME="big3 ${WORKTREE}"

udid_for_name() {
  xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data["devices"].items():
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit
' "$1"
}

case "${1:-}" in
  --delete)
    udid="$(udid_for_name "$NAME")"
    if [ -z "$udid" ]; then
      echo "No simulator named \"$NAME\"." >&2
      exit 0
    fi
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl delete "$udid"
    echo "Deleted \"$NAME\"."
    exit 0
    ;;
esac

udid="$(udid_for_name "$NAME")"

if [ -z "$udid" ]; then
  # Newest installed iOS runtime, and the requested hardware within it.
  read -r runtime_id device_type_id <<EOF
$(xcrun simctl list -j | python3 -c '
import json, sys

wanted, wanted_runtime = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)

runtimes = [r for r in data["runtimes"] if r.get("isAvailable") and r["platform"] == "iOS"]
if not runtimes:
    sys.exit("No iOS runtime installed. Open Xcode > Settings > Components and add one.")

if wanted_runtime:
    runtime = next((r for r in runtimes if r["name"] == wanted_runtime), None)
    if runtime is None:
        have = ", ".join(r["name"] for r in runtimes)
        sys.exit(f"No runtime named {wanted_runtime!r}. Installed: {have}")
else:
    runtime = max(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])

supported = {d["identifier"] for d in data["devicetypes"]}
match = next(
    (d for d in data["devicetypes"] if d["name"] == wanted and d["identifier"] in supported),
    None,
)
if match is None:
    sys.exit(f"No device type named {wanted!r}.")

print(runtime["identifier"], match["identifier"])
' "$DEVICE_TYPE" "$RUNTIME")
EOF
  udid="$(xcrun simctl create "$NAME" "$device_type_id" "$runtime_id")"
  echo "Created \"$NAME\" ($DEVICE_TYPE, ${RUNTIME:-newest installed runtime})." >&2
fi

state="$(xcrun simctl list devices -j | python3 -c '
import json, sys
udid = sys.argv[1]
data = json.load(sys.stdin)
for devices in data["devices"].values():
    for device in devices:
        if device["udid"] == udid:
            print(device["state"])
            raise SystemExit
' "$udid")"

if [ "$state" != "Booted" ]; then
  xcrun simctl boot "$udid"
  echo "Booted \"$NAME\"." >&2
fi

if [ "${1:-}" = "--udid" ]; then
  echo "$udid"
else
  echo "$NAME"
  echo "$udid" >&2
fi

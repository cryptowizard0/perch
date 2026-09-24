#!/bin/sh
# M2 acceptance: time from invoking `perch add` to the notch app having applied it and laid out the UI.
# Runs an isolated perchd + Perch.app (its own PERCH_HOME), so your real queue is untouched.
#   scripts/measure-latency.sh [runs]     # default 10; needs .build/Perch.app (scripts/bundle-app.sh)
set -eu
cd "$(dirname "$0")/.."
RUNS=${1:-10}
APP=${APP:-.build/Perch.app}
BIN=$(swift build --show-bin-path)
swift build --product perch --product perchd >/dev/null
[ -x "$APP/Contents/MacOS/Perch" ] || { echo "no $APP; run scripts/bundle-app.sh first" >&2; exit 1; }

export PERCH_HOME=$(mktemp -d /tmp/perch-lat.XXXXXX)
"$BIN/perchd" --http-port 0 >"$PERCH_HOME/perchd.log" 2>&1 &
DAEMON=$!
PERCH_LATENCY_LOG=1 "$APP/Contents/MacOS/Perch" 2>"$PERCH_HOME/app.log" &
APPPID=$!
trap 'kill $APPPID $DAEMON 2>/dev/null; wait 2>/dev/null; rm -rf "$PERCH_HOME"' EXIT

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
# Warm up: add until the app has started, connected and logs what it sees (up to ~10 s).
ready=
for _ in $(seq 20); do
    if id=$("$BIN/perch" add "warm-up" 2>/dev/null); then
        for _ in $(seq 10); do
            grep -q "perch-latency $id " "$PERCH_HOME/app.log" && { ready=1; break; }
            sleep 0.05
        done
    fi
    [ -n "$ready" ] && break
    sleep 0.5
done
[ -n "$ready" ] || { echo "the app never connected to perchd" >&2; exit 1; }

worst=0; total=0
for n in $(seq "$RUNS"); do
    start=$(now_ms)
    id=$("$BIN/perch" add "latency probe $n")
    for _ in $(seq 200); do
        line=$(grep "perch-latency $id " "$PERCH_HOME/app.log" || true)
        [ -n "$line" ] && break
        sleep 0.005
    done
    [ -n "$line" ] || { echo "run $n: app never saw $id" >&2; exit 1; }
    ms=$(( ${line##* } - start ))
    echo "run $n: ${ms} ms"
    total=$((total + ms)); [ "$ms" -gt "$worst" ] && worst=$ms
done
echo "mean $((total / RUNS)) ms, worst $worst ms (budget 200 ms)"
[ "$worst" -le 200 ]

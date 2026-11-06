#!/usr/bin/env bash
# Runs the two-process darts test (host + client over ENet on localhost).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --script res://tests/darts_net_test.gd -- host > /tmp/cp_darts_host.log 2>&1 &
HOST=$!
"$GODOT" --headless --path . --script res://tests/darts_net_test.gd -- client > /tmp/cp_darts_client.log 2>&1
C=$?
wait $HOST
H=$?
echo "--- host";   grep -E "DARTSNET|ERROR|SCRIPT" /tmp/cp_darts_host.log
echo "--- client"; grep -E "DARTSNET|ERROR|SCRIPT" /tmp/cp_darts_client.log
[ $H -eq 0 ] && [ $C -eq 0 ] && echo "DARTS NET TEST PASSED" || { echo "DARTS NET TEST FAILED"; exit 1; }

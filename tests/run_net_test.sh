#!/usr/bin/env bash
# Runs the two-process co-op test (host + client over ENet on localhost).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --script res://tests/net_test.gd -- host > /tmp/cp_net_host.log 2>&1 &
HOST=$!
"$GODOT" --headless --path . --script res://tests/net_test.gd -- client > /tmp/cp_net_client.log 2>&1
C=$?
wait $HOST
H=$?
echo "--- host";   grep -E "NET|ERROR|SCRIPT" /tmp/cp_net_host.log
echo "--- client"; grep -E "NET|ERROR|SCRIPT" /tmp/cp_net_client.log
[ $H -eq 0 ] && [ $C -eq 0 ] && echo "NET TEST PASSED" || { echo "NET TEST FAILED"; exit 1; }

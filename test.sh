#!/usr/bin/env bash
source .akku/bin/activate

# Clean up leftover test server processes
ps aux | grep "http-pixiu-test" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
ps aux | grep "scheme --script /tmp/http-pixiu" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
ps aux | grep "scheme --script /tmp/test" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null

skip=(
    # "./tests/output-identifier-types.sps" 
    # "./tests/parallel-log-debug.sps" 
    # "./tests/log-debug.sps" 
)

success=0

for test in $(find ./tests | grep ".sps$")
do
    if [[ "${skip[@]}" =~ $test ]]; then continue; fi
    scheme --quiet $test
    success=$(($? || $success))
done;

exit $success
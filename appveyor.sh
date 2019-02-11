#!/bin/bash -x
set +e
./start-build &
sleep 5
timeout 25m tail -f tmp/build/ruby-trunk/*/log || true

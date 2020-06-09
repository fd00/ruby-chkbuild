#!/bin/bash -x
set +e
./start-build &
sleep 3
timeout 50m tail -f tmp/build/ruby-master/*/log || true

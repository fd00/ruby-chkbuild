#!/bin/bash -x
set +e
./start-build &
sleep 5
timeout 20m tail -f tmp/build/ruby-master/*/log || true

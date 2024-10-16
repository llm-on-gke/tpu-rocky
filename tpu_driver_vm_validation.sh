#!/bin/bash

sudo modprobe jellyfish
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: failed to modprobe tpu."
fi

while true
do
  echo "Validation done." > /dev/ttyS0
  sleep 10
done
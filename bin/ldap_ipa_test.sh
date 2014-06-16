#!/bin/bash
echo "Testing if DNS is setup correctly"

echo "The below should return an IP Address"
ifconfig eth0 | grep addr

echo "Second command, needs more investigation for correct response."
dig -t ptr `hostname  -I | cut -f1 -d' ' | rev`.in-addr.arpa.


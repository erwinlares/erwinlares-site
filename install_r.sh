#!/bin/bash
set -e

echo "=== Installing R via apt ==="
apt-get update -qq
apt-get install -y --no-install-recommends r-base

echo "=== Testing Rscript ==="
which Rscript
Rscript --version
#!/bin/bash
set -e

R_VERSION=${R_VERSION:-"4.4.2"}

echo "=== OS info ==="
lsb_release -a

echo "=== Downloading R ==="
wget -qO /tmp/R.deb "https://cdn.rstudio.com/r/ubuntu-2404/pkgs/r-${R_VERSION}_1_amd64.deb"
echo "Download exit code: $?"

echo "=== Extracting ==="
mkdir -p $HOME/R-${R_VERSION}
dpkg-deb -x /tmp/R.deb $HOME/R-${R_VERSION}

echo "=== Locating Rscript ==="
find $HOME/R-${R_VERSION} -name "Rscript"

echo "=== Creating symlinks ==="
mkdir -p $HOME/.local/bin
ln -sf "$HOME/R-${R_VERSION}/opt/R/${R_VERSION}/bin/R" $HOME/.local/bin/R
ln -sf "$HOME/R-${R_VERSION}/opt/R/${R_VERSION}/bin/Rscript" $HOME/.local/bin/Rscript

echo "=== Testing Rscript ==="
export PATH=$HOME/.local/bin:$PATH
which Rscript
Rscript --version
#!/bin/bash
set -e

R_VERSION=${R_VERSION:-"4.4.2"}

wget -qO /tmp/R.deb "https://cdn.rstudio.com/r/ubuntu-2404/pkgs/r-${R_VERSION}_1_amd64.deb"
mkdir -p $HOME/R-${R_VERSION}
dpkg-deb -x /tmp/R.deb $HOME/R-${R_VERSION}

mkdir -p $HOME/.local/bin
ln -sf "$HOME/R-${R_VERSION}/opt/R/${R_VERSION}/bin/R" $HOME/.local/bin/R
ln -sf "$HOME/R-${R_VERSION}/opt/R/${R_VERSION}/bin/Rscript" $HOME/.local/bin/Rscript

export PATH=$HOME/.local/bin:$PATH
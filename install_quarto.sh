#!/bin/bash
set -e
wget -qO quarto.tar.gz "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
tar -xzf quarto.tar.gz
mkdir -p $HOME/.local/bin
ln -s "$(pwd)/quarto-${QUARTO_VERSION}/bin/quarto" $HOME/.local/bin/quarto
export PATH=$HOME/.local/bin:$PATH
quarto render
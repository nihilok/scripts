#!/bin/bash

set -e

sudo apt update

sudo apt install git zsh -y

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"


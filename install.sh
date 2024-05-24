#!/bin/bash

set -e

BIN_DIR=/usr/local/bin
INSTALL_DIR=$HOME/.purman/bin
DOWNLOAD_DIR=$(mktemp -d)
GIT_REPO_URL="https://github.com/CaffeineDuck/purman.git"

function _bare_install() {
  if [[ -d "$INSTALL_DIR" || -f "$BIN_DIR/purman" ]]; then
    echo "Purman already installed. Exiting."
  fi

  echo "Creating the directory $INSTALL_DIR"
  mkdir -p $INSTALL_DIR

  echo "Moving necessary files to $INSTALL_DIR"
  cp -r helpers $INSTALL_DIR/helpers
  cp purman.sh $INSTALL_DIR/purman.sh

  echo "Creating a symlink to $INSTALL_DIR/purman.sh -> $BIN_DIR/purman"
  sudo ln -s $INSTALL_DIR/purman.sh $BIN_DIR/purman

  echo "Purman installed successfully."
}

function _bare_download() {
  mkdir -p $DOWNLOAD_DIR
  git clone $GIT_REPO_URL $DOWNLOAD_DIR
}

function download_and_install() {
  if [[ -d $INSTALL_DIR ]]; then
    echo "Purman is already installed. Exiting."
    exit 1
  fi

  if [[ -d $DOWNLOAD_DIR ]]; then
    rm -r $DOWNLOAD_DIR
  fi

  _bare_download

  cd $DOWNLOAD_DIR

  _bare_install
}

function cleanup() {
  if [[ -d $DOWNLOAD_DIR ]]; then
    echo "Deleting $DOWNLOAD_DIR"
    rm -r $DOWNLOAD_DIR
  fi

  if [[ -d $INSTALL_DIR ]]; then
    echo "Deleting $INSTALL_DIR"
    rm -r $INSTALL_DIR
  fi

  if [[ -L "$BIN_DIR/purman" ]]; then
    echo "Deleting $BIN_DIR/purman symlink."
    sudo rm $BIN_DIR/purman
  fi

  echo "Cleanup done."
}

function update_and_install() {
  if [[ ! -d $INSTALL_DIR ]]; then
    echo "Purman is not installed. Exiting."
    exit 1
  fi

  cleanup
  download_and_install
}

function install_dev() {
  cleanup
  _bare_install
}

HELP_TEXT="
Purman Installer 

Usage: $0 <command>

Options:
    help            Show this help message
    install       Download and install purman from github
    install_dev     Install the current directory as purman
    update          Update purman to the latest version
    uninstall       Remove purman from the system
"

case $1 in
install)
  download_and_install
  ;;
install_dev)
  install_dev
  ;;
update)
  update_and_install
  ;;
uninstall)
  cleanup
  ;;
help)
  echo "$HELP_TEXT"
  ;;
*)
  if [[ -z "$1" ]]; then
    echo "No command provided."
    echo "$HELP_TEXT"
    exit 1
  fi

  echo "Invalid command: $1"
  echo "$HELP_TEXT"
  ;;
esac

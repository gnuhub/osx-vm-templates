#!/usr/bin/env bash
chmod +x  prepare_iso/prepare_iso.sh
BUILD_TIME=$(date +%Y%m%d_%H%m%S)
sudo prepare_iso/prepare_iso.sh "/Users/stallman/gnuhubdata/git/osx-vm-templates/Install OS X Mavericks.app" out > ${BUILD_TIME}.log 2>&1 
#!/usr/bin/env bash
#https://github.com/mitchellh/packer/issues/1552
#export FUSION_APP_PATH="${HOME}/Applications/VMware Fusion.app"
cd packer
packer build \
  -only=vmware-iso \
  -var iso_checksum=7473deaeddfe7919ad3482a4c8ef7560 \
  -var iso_url=../out/OSX_InstallESD_10.9.5_13F34.dmg \
  template.json
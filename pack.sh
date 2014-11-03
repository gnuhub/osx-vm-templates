#!/usr/bin/env bash
#https://github.com/mitchellh/packer/issues/1552
export FUSION_APP_PATH="${HOME}/Applications/VMware Fusion.app"
cd packer
packer build \
  -only=vmware-iso \
  -var iso_checksum=7ebc054e4c51fe2df2f486f826ecf005 \
  -var iso_url=../out/OSX_InstallESD_10.9.4_13E28.dmg \
  template.json
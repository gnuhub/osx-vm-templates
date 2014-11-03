#!/usr/bin/env bash
#sudo prepare_iso/prepare_iso.sh "/Users/stallman/gnuhubdata/download/MACOSX10.9.4_0.dmg" out


#!/bin/sh
#
# Preparation script for an OS X automated installation for use with VeeWee/Packer/Vagrant
# 
# What the script does, in more detail:
# 
# 1. Mounts the InstallESD.dmg using a shadow file, so the original DMG is left
#    unchanged.
# 2. Modifies the BaseSystem.dmg within in order to add an additional 'rc.cdrom.local'
#    file in /etc, which is a supported local configuration sourced in at boot time
#    by the installer environment. This file contains instructions to erase and format
#    'disk0', presumably the hard disk attached to the VM.
# 3. A 'veewee-config.pkg' installer package is built, which is added to the OS X
#    install by way of the OSInstall.collection file. This package creates the
#    'vagrant' user, configures sshd and sudoers, and disables setup assistants.
# 4. veewee-config.pkg and the various support utilities are copied, and the disk
#    image is saved to the output path.
#
# Thanks:
# Idea and much of the implementation thanks to Pepijn Bruienne, who's also provided
# some process notes here: https://gist.github.com/4542016. The sample minstallconfig.xml,
# use of OSInstall.collection and readme documentation provided with Greg Neagle's
# createOSXInstallPkg tool also proved very helpful. (http://code.google.com/p/munki/wiki/InstallingOSX)
# User creation via package install method also credited to Greg, and made easy with Per
# Olofsson's CreateUserPkg (http://magervalp.github.io/CreateUserPkg)
set -x
usage() {
	cat <<EOF
Usage:
$(basename "$0") "/path/to/InstallESD.dmg" /path/to/output/directory
$(basename "$0") "/path/to/Install OS X [Mountain] Lion.app" /path/to/output/directory

Description:
Converts a 10.7/10.8/10.9 installer image to a new image that contains components
used to perform an automated installation. The new image will be named
'OSX_InstallESD_[osversion].dmg.'

EOF
}

msg_status() {
	echo "\033[0;32m-- $1\033[0m"
}
msg_error() {
	echo "\033[0;31m-- $1\033[0m"
}

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

if [ $(id -u) -ne 0 ]; then
	msg_error "This script must be run as root, as it saves a disk image with ownerships enabled."
	exit 1
fi	




SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
VEEWEE_DIR="$(cd "$SCRIPT_DIR/../../../"; pwd)"
VEEWEE_UID=$(stat -f %u "$VEEWEE_DIR")
VEEWEE_GID=$(stat -f %g "$VEEWEE_DIR")
DEFINITION_DIR="$(cd '$SCRIPT_DIR/..'; pwd)"


OUT_DIR="$2"
if [ ! -d "$OUT_DIR" ]; then
	msg_status "Destination dir $OUT_DIR doesn't exist, creating.."
	mkdir -p "$OUT_DIR"
fi




msg_status "Mounting BaseSystem.."
BASE_SYSTEM_DMG="$1"

MNT_BASE_SYSTEM=$(/usr/bin/mktemp -d ${HOME}/gnuhubdata/tmp/veewee-osx-basesystem.XXXX)
[ ! -e "$BASE_SYSTEM_DMG" ] && msg_error "Could not find BaseSystem.dmg"
hdiutil attach "$BASE_SYSTEM_DMG" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on
if [ $? -ne 0 ]; then
	msg_error "Could not mount $BASE_SYSTEM_DMG"
	exit 1
fi
SYSVER_PLIST_PATH="$MNT_BASE_SYSTEM/System/Library/CoreServices/SystemVersion.plist"

DMG_OS_VERS=$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' "$SYSVER_PLIST_PATH")
DMG_OS_VERS_MAJOR=$(echo $DMG_OS_VERS | awk -F "." '{print $2}')
DMG_OS_VERS_MINOR=$(echo $DMG_OS_VERS | awk -F "." '{print $3}')
DMG_OS_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$SYSVER_PLIST_PATH")
msg_status "OS X version detected: 10.$DMG_OS_VERS_MAJOR.$DMG_OS_VERS_MINOR, build $DMG_OS_BUILD"

OUTPUT_DMG="$OUT_DIR/OSX_InstallESD_${DMG_OS_VERS}_${DMG_OS_BUILD}.dmg"
if [ -e "$OUTPUT_DMG" ]; then
	msg_error "Output file $OUTPUT_DMG already exists! We're not going to overwrite it, exiting.."
	hdiutil detach -force "$MNT_ESD"
	exit 1
fi

SUPPORT_DIR="$SCRIPT_DIR/support"

# Build our post-installation pkg that will create a vagrant user and enable ssh
msg_status "Making firstboot installer pkg.."

# payload items
mkdir -p "$SUPPORT_DIR/pkgroot/private/var/db/dslocal/nodes/Default/users"
mkdir -p "$SUPPORT_DIR/pkgroot/private/var/db/shadow/hash"
cp "$SUPPORT_DIR/vagrant.plist" "$SUPPORT_DIR/pkgroot/private/var/db/dslocal/nodes/Default/users/vagrant.plist"
VAGRANT_GUID=$(/usr/libexec/PlistBuddy -c 'Print :generateduid:0' "$SUPPORT_DIR/vagrant.plist")
cp "$SUPPORT_DIR/shadowhash" "$SUPPORT_DIR/pkgroot/private/var/db/shadow/hash/$VAGRANT_GUID"

# postinstall script
mkdir -p "$SUPPORT_DIR/tmp/Scripts"
cp "$SUPPORT_DIR/pkg-postinstall" "$SUPPORT_DIR/tmp/Scripts/postinstall"
# executability should be copied over, warn if we had to chmod again
if [ ! -x "$SUPPORT_DIR/tmp/Scripts/postinstall" ]; then
	msg_status "'postinstall' script was for some reason not executable. Setting it again now, but it should have been already set when copying the definition."
	chmod a+x "$SUPPORT_DIR/tmp/Scripts/postinstall"
fi

# build it
BUILT_COMPONENT_PKG="$SUPPORT_DIR/tmp/veewee-config-component.pkg"
BUILT_PKG="$SUPPORT_DIR/tmp/veewee-config.pkg"
pkgbuild --quiet \
	--root "$SUPPORT_DIR/pkgroot" \
	--scripts "$SUPPORT_DIR/tmp/Scripts" \
	--identifier com.vagrantup.veewee-config \
	--version 0.1 \
	"$BUILT_COMPONENT_PKG"
productbuild \
	--package "$BUILT_COMPONENT_PKG" \
	"$BUILT_PKG"
rm -rf "$SUPPORT_DIR/pkgroot"

# We'd previously mounted this to check versions
hdiutil detach "$MNT_BASE_SYSTEM"

BASE_SYSTEM_DMG_RW="$(/usr/bin/mktemp /tmp/veewee-osx-basesystem-rw.XXXX).dmg"

msg_status "Converting BaseSystem.dmg to a read-write DMG located at $BASE_SYSTEM_DMG_RW.."
# hdiutil convert -o will actually append .dmg to the filename if it has no extn
hdiutil convert -format UDRW -o "$BASE_SYSTEM_DMG_RW" "$BASE_SYSTEM_DMG"

if [ $DMG_OS_VERS_MAJOR -ge 9 ]; then
	msg_status "Growing new BaseSystem.."
	hdiutil resize -size 6G "$BASE_SYSTEM_DMG_RW"
fi

msg_status "Mounting new BaseSystem.."
hdiutil attach "$BASE_SYSTEM_DMG_RW" -mountpoint "$MNT_BASE_SYSTEM" -nobrowse -owners on
if [ $DMG_OS_VERS_MAJOR -ge 9 ]; then
	rm "$MNT_BASE_SYSTEM/System/Installation/Packages"
	msg_status "Moving 'Packages' directory from the ESD to BaseSystem.."
	mv -v "$MNT_ESD/Packages" "$MNT_BASE_SYSTEM/System/Installation/"
	PACKAGES_DIR="$MNT_BASE_SYSTEM/System/Installation/Packages"
else
	PACKAGES_DIR="$MNT_ESD/Packages"
fi

msg_status "Adding automated components.."
CDROM_LOCAL="$MNT_BASE_SYSTEM/private/etc/rc.cdrom.local"
echo "diskutil eraseDisk jhfs+ \"Macintosh HD\" GPTFormat disk0" > "$CDROM_LOCAL"
chmod a+x "$CDROM_LOCAL"
mkdir "$PACKAGES_DIR/Extras"
cp "$SUPPORT_DIR/minstallconfig.xml" "$PACKAGES_DIR/Extras/"
cp "$SUPPORT_DIR/OSInstall.collection" "$PACKAGES_DIR/"
cp "$BUILT_PKG" "$PACKAGES_DIR/"
rm -rf "$SUPPORT_DIR/tmp"

msg_status "Unmounting BaseSystem.."
hdiutil detach "$MNT_BASE_SYSTEM"

if [ $DMG_OS_VERS_MAJOR -lt 9 ]; then
	msg_status "Pre-Mavericks we save back the modified BaseSystem to the root of the ESD."
	rm "$MNT_ESD/BaseSystem.dmg"
	hdiutil convert -format UDZO -o "$MNT_ESD/BaseSystem.dmg" "$BASE_SYSTEM_DMG_RW"
fi



if [ $DMG_OS_VERS_MAJOR -ge 9 ]; then
	msg_status "On Mavericks the entire modified BaseSystem is our output dmg."
	hdiutil convert -format UDZO -o "$OUTPUT_DMG" "$BASE_SYSTEM_DMG_RW"
else
	msg_status "Pre-Mavericks we're modifying the original ESD file."
	hdiutil convert -format UDZO -o "$OUTPUT_DMG" -shadow "$SHADOW_FILE" "$ESD"
fi
rm -rf "$MNT_ESD" "$SHADOW_FILE"

if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
	msg_status "Fixing permissions.."
	chown -R $SUDO_UID:$SUDO_GID \
		"$OUT_DIR"
fi

if [ -n "$DEFAULT_ISO_DIR" ]; then
	DEFINITION_FILE="$DEFINITION_DIR/definition.rb"
	msg_status "Setting ISO file in definition "$DEFINITION_FILE".."
	ISO_FILE=$(basename "$OUTPUT_DMG")
	# Explicitly use -e in order to use double quotes around sed command
	sed -i -e "s/%OSX_ISO%/${ISO_FILE}/" "$DEFINITION_FILE"
fi

msg_status "Checksumming output image.."
MD5=$(md5 -q "$OUTPUT_DMG")
msg_status "MD5: $MD5"

msg_status "Done. Built image is located at $OUTPUT_DMG. Add this iso and its checksum to your template."

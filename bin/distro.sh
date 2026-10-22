#! /bin/bash
# ------------------------------------------------------------------
# Distro abstraction layer. Sourced by 73.sh, runner.sh, remove.sh
# and app-check.sh so every .bapp file can use these helpers.
#
# .bapp files keep using Debian package names. On openSUSE the names
# are translated with the SUSE_PKG table below. A name mapped to ""
# is skipped on openSUSE. Names not in the table are passed through.
# ------------------------------------------------------------------

BAPOS=$(. /etc/os-release 2>/dev/null; echo "$ID $ID_LIKE")
if echo "$BAPOS" | grep -qi suse; then
	IS_SUSE=1
else
	IS_SUSE=
fi

#use the askpass helper once runner.sh has set it up
_sudo(){
	if [ -n "$SUDO_ASKPASS" ]; then
		sudo -A "$@"
	else
		sudo "$@"
	fi
}

#where files from .deb packages extracted on openSUSE are tracked
DEBTRACK=/var/lib/73linux

#OBS repos needed on openSUSE Tumbleweed
SUSE_HAMRADIO_REPO=https://download.opensuse.org/repositories/hamradio/openSUSE_Tumbleweed/
SUSE_GNOMEAPPS_REPO=https://download.opensuse.org/repositories/GNOME:/Apps/openSUSE_Factory/

declare -A SUSE_PKG=(
	#base
	[build-essential]="gcc gcc-c++ make"
	[extra-xdg-menus]=""
	[libfuse2]="libfuse2"
	#ax25 / conky
	[conky-all]=""
	[conky-std]=""
	[ruby-full]="ruby ruby-devel"
	#cqrlog
	[lcl-2.0]=""
	[lcl]=""
	[fp-utils]=""
	[fp-units-misc]=""
	[fp-units-gfx]=""
	[fp-units-gtk2]=""
	[fp-units-db]=""
	[fp-units-math]=""
	[fp-units-net]=""
	[libssl-dev]="libopenssl-devel"
	[mariadb-server]="mariadb"
	[default-libmysqlclient-dev]="libmariadb-devel"
	#fl suite
	[libfltk1.3-dev]="fltk-devel"
	[libfltk1.3-compat-headers]=""
	[libjpeg62-dev]="libjpeg8-devel"
	[libxft-dev]="libXft-devel"
	[libxinerama-dev]="libXinerama-devel"
	[libxcursor-dev]="libXcursor-devel"
	[libsndfile1-dev]="libsndfile-devel"
	[libsamplerate0-dev]="libsamplerate-devel"
	[portaudio19-dev]="portaudio-devel"
	[libpulse-dev]="libpulse-devel"
	[libusb-1.0-0]="libusb-1_0-0"
	[libusb-1.0-0-dev]="libusb-1_0-devel"
	[libudev-dev]="systemd-devel"
	#hamlib
	[libnova-0.16-0]=""
	[libnova-dev]="libnova-devel"
	[libindi-dev]="indi-devel"
	[libindi-data]=""
	[libindi-plugins]=""
	[libgd-dev]="gd-devel"
	#gps
	[python3-gps]="python3-gpsd"
	[python3-gi-cairo]="python3-gobject-cairo"
	[libgps-dev]="gpsd-devel"
	#direwolf
	[libasound2-dev]="alsa-devel"
	#java apps
	[librxtx-java]="rxtx-java"
	[openjdk-17-dbg]="java-21-openjdk"
	#security
	[nemo-seahorse]="nemo-extension-seahorse"
	[caja-seahorse]=""
	[seahorse-nautilus]="nautilus-extension-seahorse"
	[gtkhash]=""
	#chirp
	[python3-wxgtk4.0]="python3-wxPython"
	#repeater start
	[gir1.2-osmgpsmap-1.0]="typelib-1_0-OsmGpsMap-1_0 python3-gobject python3-gobject-cairo xdg-utils"
	[gir1.2-geoclue-2.0]="typelib-1_0-Geoclue-2_0"
	[libosmgpsmap-1.0-1]="libosmgpsmap-1_0-1"
	#misc
	[pandoc]="pandoc-cli"
	[wine-stable]="wine wine-32bit"
	[xygrib]="XyGrib"
	[xygrib-maps]=""
)

#translate Debian package names to the local distro
PKG_NAMES(){
	local p
	for p in "$@"; do
		if [ -n "$IS_SUSE" ] && [ -n "${SUSE_PKG[$p]+set}" ]; then
			echo ${SUSE_PKG[$p]}
		else
			echo $p
		fi
	done | tr '\n' ' '
}

#refresh package lists
PKG_UPDATE(){
	if [ -n "$IS_SUSE" ]; then
		_sudo zypper --non-interactive --gpg-auto-import-keys refresh
	else
		_sudo apt update
	fi
}

#install packages from the distro repos (takes Debian names)
PKG_INSTALL(){
	local PKGS=$(PKG_NAMES "$@")
	[ -z "${PKGS// /}" ] && return 0
	if [ -n "$IS_SUSE" ]; then
		#zypper aborts the whole transaction when one package is
		#missing, so fall back to installing one at a time
		if ! _sudo zypper --non-interactive install --auto-agree-with-licenses ${PKGS}; then
			local p
			for p in ${PKGS}; do
				_sudo zypper --non-interactive install --auto-agree-with-licenses $p ||
					echo "WARNING: could not install $p"
			done
		fi
	else
		_sudo apt install -y ${PKGS}
	fi
}

#remove packages (takes Debian names)
PKG_REMOVE(){
	local PKGS=$(PKG_NAMES "$@")
	[ -z "${PKGS// /}" ] && return 0
	if [ -n "$IS_SUSE" ]; then
		local p
		for p in ${PKGS}; do
			_sudo zypper --non-interactive remove --clean-deps $p
		done
	else
		_sudo apt purge -y ${PKGS}
	fi
}

#install a downloaded package file (.deb on Debian, .rpm on openSUSE)
PKG_INSTALL_FILE(){
	if [ -n "$IS_SUSE" ]; then
		_sudo zypper --non-interactive install --allow-unsigned-rpm "$(realpath "$1")"
	else
		_sudo apt install -y "$(realpath "$1")"
	fi
}

#install a .deb on a system without dpkg by unpacking it into /.
#Maintainer scripts are not run. Installed files are recorded in
#$DEBTRACK so DEB_REMOVE can clean them up again.
DEB_EXTRACT(){
	local DEB=$(realpath "$1")
	local TMP=$(mktemp -d)
	(
		cd ${TMP} || exit 1
		ar x "${DEB}" || exit 1
		mkdir control data
		tar -xf control.tar.* -C control
		tar -xf data.tar.* -C data
		#merged /usr: /bin, /lib etc. are symlinks on Tumbleweed
		for d in bin sbin lib lib64; do
			if [ -L /$d ] && [ -d data/$d ]; then
				mkdir -p data/usr/$d
				cp -a data/$d/. data/usr/$d/
				rm -rf data/$d
			fi
		done
		NAME=$(grep ^Package: control/control | awk '{print $2}')
		VER=$(grep ^Version: control/control | awk '{print $2}')
		_sudo mkdir -p ${DEBTRACK}
		(cd data && find . ! -type d | sed 's/^\.//') | _sudo tee ${DEBTRACK}/${NAME}.files >/dev/null
		echo ${VER} | _sudo tee ${DEBTRACK}/${NAME}.version >/dev/null
		_sudo cp -a --no-preserve=ownership data/. /
	)
	rm -rf ${TMP}
	if hash systemctl 2>/dev/null; then
		_sudo systemctl daemon-reload
	fi
}

#remove a package that was installed with DEB_EXTRACT
DEB_REMOVE(){
	if [ ! -f ${DEBTRACK}/$1.files ]; then
		echo "$1 was not installed by 73 Linux"
		return 1
	fi
	while read -r f; do
		_sudo rm -f "$f"
	done <${DEBTRACK}/$1.files
	_sudo rm -f ${DEBTRACK}/$1.files ${DEBTRACK}/$1.version
}

#install a .deb natively on Debian or by extraction on openSUSE
PKG_INSTALL_DEB(){
	if [ -n "$IS_SUSE" ]; then
		DEB_EXTRACT "$1"
	else
		_sudo apt install -y "$(realpath "$1")"
	fi
}

#remove a package installed with PKG_INSTALL_FILE or PKG_INSTALL_DEB
PKG_REMOVE_LOCAL(){
	if [ -n "$IS_SUSE" ] && [ -f ${DEBTRACK}/$1.files ]; then
		DEB_REMOVE $1
	elif [ -n "$IS_SUSE" ]; then
		_sudo zypper --non-interactive remove $1
	else
		_sudo dpkg --remove $1
	fi
}

#print the installed version of a package, empty if not installed
PKG_VERSION(){
	if [ -n "$IS_SUSE" ] && [ -f ${DEBTRACK}/$1.version ]; then
		cat ${DEBTRACK}/$1.version
	elif [ -n "$IS_SUSE" ]; then
		rpm -q --qf '%{VERSION}' $1 2>/dev/null | grep -v 'not installed'
	else
		dpkg-query -W -f='${Version}' $1 2>/dev/null
	fi
}

#print the version of a package available in the repos
PKG_REPO_VERSION(){
	if [ -n "$IS_SUSE" ]; then
		zypper --no-refresh --quiet info $1 2>/dev/null | grep ^Version | head -1 | awk '{print $3}' | sed 's/-.*//'
	else
		apt show $1 2>/dev/null | grep ^Version | awk '{print $2}'
	fi
}

#one time openSUSE setup: OBS repos and packages Debian ships by default
SUSE_SETUP(){
	[ -z "$IS_SUSE" ] && return 0
	if ! zypper lr -u | grep -q "repositories/hamradio/openSUSE_Tumbleweed"; then
		echo "Adding openSUSE hamradio repository"
		_sudo zypper --non-interactive addrepo --refresh ${SUSE_HAMRADIO_REPO} hamradio
	fi
	#yad lives in GNOME:Apps. Low priority so it only supplies what
	#the main repos lack.
	if ! zypper lr -u | grep -q "repositories/GNOME:/Apps/"; then
		echo "Adding openSUSE GNOME:Apps repository (for yad)"
		_sudo zypper --non-interactive addrepo --refresh --priority 120 ${SUSE_GNOMEAPPS_REPO} GNOME_Apps
	fi
	_sudo zypper --non-interactive --gpg-auto-import-keys refresh
	#crontab, AppImage support, ar for .deb extraction, alsa pulse plugin
	_sudo zypper --non-interactive install cronie libfuse2 binutils alsa-plugins-pulse unzip wget curl
	_sudo systemctl enable --now cron.service
}

#source builds install to /usr/local which openSUSE's pkg-config
#does not search by default (Debian does)
if [ -n "$IS_SUSE" ]; then
	export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
fi

export IS_SUSE

#!/usr/bin/env bash

function _realpath() {
	python3 -c "import os; print(os.path.realpath('$1'))"
}

function installed() {
	executable="$1"
	command -v "$executable" >/dev/null 2>&1
}

function getgo() {
	url=$1
	prefix=$2

	gopkg="$(basename "$url")"
	os="$(uname | tr '[:upper:]' '[:lower:]')"

	[ -z "$gopkg" ] && echo "Fatal: invalid url $url" && return 255

	[ -z "$prefix" ] && {
		[ "$os" == "linux" ] && prefix=/opt
		[ "$os" == "darwin" ] && prefix=/usr/local/opt
	}
	go_root="$prefix/go"
	[ -d "$go_root" ] && echo "removing old $go_root" && rm -rf "$go_root"
	wd="$(mktemp -d "${TMPDIR:-/tmp}"/go.XXXXXXXXXXXXXXXX 2>/dev/null)"
	[ -d "$wd" ] || wd=/tmp/$(date +%s) && mkdir -p "$wd"
	pkg="$wd/$gopkg"
	[ ! -f "$gopkg" ] && echo "downloading $gopkg from $url" && curl -L --progress-bar -o "$pkg" "$url"
	[ ! -d "$prefix" ] && echo "creating directory : $prefix" && mkdir -p "$prefix"
	pushd "$prefix" >/dev/null 2>&1 || return 255
	echo "extracting $gopkg to $prefix/go ... " && tar xf "$pkg"
	popd >/dev/null 2>&1 || return 255

	[ ! -d "$go_root" ] && echo "Fatal: installation failed, go root not found" && return 255
	[ ! -d "$go_root/bin" ] && echo "Fatal: installation failed, go bin not found" && return 255

	for file in "$go_root"/bin/*; do
		bin="$(basename "$file")"
		if installed update-alternatives; then
			update-alternatives --install /usr/bin/"$bin" "$bin" "$(_realpath "$file")" 1
		else
			rm -rf /usr/local/bin/"${bin:?}" && ln -s "$(_realpath "$file")" /usr/local/bin/"${bin:?}"
		fi
	done
}

if ((EUID != 0)); then
	echo "Granting root privileges for ""$(basename "$0")"
	script=$(_realpath "$0")
	if [ -t 1 ]; then
		sudo "$script" "$@"
	else
		exec 1>output_file
		gksu "$script" "$@"
	fi
	exit
fi

os="$(uname | tr '[:upper:]' '[:lower:]')"
if [ "$os" != "linux" ] && [ "$os" != "darwin" ]; then
	echo "this script is linux/macOS only" && exit 255
fi

arch=""
case $(uname -m) in
i386 | i686) arch="386" ;;
x86_64) arch="amd64" ;;
aarch64 | arm64) arch="arm64" ;;
armv6l) arch="armv6l" ;;
esac

[ -z "$arch" ] && echo "Fatal: can not determine system arch" && exit 255

go_dl_base="https://go.dev/dl/"
go_dl_root="https://go.dev"
go_url="$(curl -s "$go_dl_base" | grep -Eo "a class=\"download\" href=.*go.*$os-$arch.tar.gz\"" | head -n1 | cut -d'"' -f4)"
go_version="$(go version 2>/dev/null | awk '{print $3}')"
remote_version="$(basename "$go_url" | sed -e 's/.'"$os"'-.*.tar.gz//')"
[ -n "$go_url" ] && [ "$go_version" != "$remote_version" ] && getgo "$go_dl_root$go_url"

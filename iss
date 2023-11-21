#!/usr/bin/env bash

password=""

POSITIONAL=()

while [ $# -gt 0 ]; do
    case "$1" in
    -p | --password)
        password="$2"
        shift 2
        ;;
    *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

base_url="https://debian.lol"
github_base="https://raw.githubusercontent.com/mysqto/install/gh-pages"

# check connection to base url
if ! curl -sL --connect-timeout 5 "$base_url" >/dev/null 2>&1; then
    echo "Failed to connect to $base_url"
    echo "try to use github url $github_base"
    base_url="$github_base"
    # check connection to base url again
    if ! curl -sL --connect-timeout 5 "$base_url" >/dev/null 2>&1; then
        echo "Failed to connect to $base_url"
        exit 1
    fi
fi

if [ -z "$password" ]; then
    curl -sL "$base_url/ss-libev" | bash -s --
else
    curl -sL "$base_url/ss-libev" | bash -s -- --password "$password"
fi

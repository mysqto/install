#!/usr/bin/env bash

password=""

POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p | --password ) password="$2"; shift 2 ;;
        * ) POSITIONAL+=("$1"); shift ;;
    esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ -z "$password" ]]; then
    curl -sL install.lol/ss-libev | bash -s --
else
    curl -sL install.lol/ss-libev | bash -s -- -p "$password"
fi

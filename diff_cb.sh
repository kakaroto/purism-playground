#!/bin/bash

a=$1
b=$2

if [[ ! -f "$a" ]] || [[ ! -f "$b" ]]; then
    echo "Input file does not exit"
    exit 1
fi

base_a="$(basename "$a").cbfs"
base_b="$(basename "$b").cbfs"
mkdir -p "$base_a"
mkdir -p "$base_b"

IFS=$'\n'
for line in $(./cbfstool "$a" print 2>/dev/null); do
    name="$(echo "$line" | cut -d' ' -f 1)"
    if [[ "$name" == "Name" ]] || [[ "$name" == "cbfs" ]] || [[ "$name" == "(empty)" ]]; then
        continue
    fi

    mkdir -p "$base_a/$(dirname "$name")"
    if [ "$(echo "$line" | grep 'stage\|payload')" == "" ]; then
        ./cbfstool "$a" extract -n "$name" -f "$base_a/$name" 2>/dev/null
    else
        ./cbfstool "$a" extract -n "$name" -f "$base_a/$name" -m x86 2>/dev/null
    fi
done

for line in $(./cbfstool "$b" print 2>/dev/null); do
    name="$(echo "$line" | cut -d' ' -f 1)"
    if [[ "$name" == "Name" ]] || [[ "$name" == "cbfs" ]] || [[ "$name" == "(empty)" ]]; then
        continue
    fi
    mkdir -p "$base_b/$(dirname "$name")"
    if [ "$(echo "$line" | grep 'stage\|payload')" == "" ]; then
        ./cbfstool "$b" extract -n "$name" -f "$base_b/$name" 2>/dev/null
    else
        ./cbfstool "$b" extract -n "$name" -f "$base_b/$name" -m x86 2>/dev/null
    fi
done

diff -u <(cd "$base_a" && find "." -type f | xargs sha1sum) <(cd "$base_b" && find "." -type f | xargs sha1sum)

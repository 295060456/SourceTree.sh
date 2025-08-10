#!/bin/zsh

# 用SourceTree运行此脚本，不会继承当前的Shell。需要做一些额外的操作
cd "${1:-$PWD}" || exit 1

rm -f ~/.jenv/shims/.jenv-shim
jenv local openjdk64-17.0.16
eval "$(jenv init -)"
jenv rehash
jenv shell openjdk64-17.0.16;

exec studio .

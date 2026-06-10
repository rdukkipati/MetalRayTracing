#!/bin/zsh
mkdir -p build
pushd build
clang++ -g -O0 ../game/code/main.mm -o MetalRayTracing -framework Cocoa
popd

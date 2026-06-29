#!/bin/zsh
mkdir -p build
pushd build
xcrun -sdk macosx metal -c ../RayTracing/code/shaders.metal -o shaders.air -Wno-unused-function
xcrun -sdk macosx metallib shaders.air -o shaders.metallib
clang++ -g -O0  ../RayTracing/code/main.mm -o MetalRayTracing -framework Foundation -framework Metal -Wno-unused-function
popd

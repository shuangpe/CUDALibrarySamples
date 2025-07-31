#!/bin/bash

set -e

SCRIPT_DIR=$(dirname "$(realpath $0)")

build_fp16_gemm() {
    echo "Building FP16 GEMM sample..."
    pushd $PWD
    BUILD_DIR="$SCRIPT_DIR/cuBLASLt/LtHSHgemmStridedBatchSimple/build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j32
    popd
}

build_mxfp8_gemm() {
    echo "Building MXFP8 GEMM sample..."
    pushd $PWD
    BUILD_DIR="$SCRIPT_DIR/cuBLASLt/LtMxfp8Matmul/build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j32
    popd
}

build_nvfp4_gemm() {
    echo "Building NVFP4 GEMM sample..."
    pushd $PWD
    BUILD_DIR="$SCRIPT_DIR/cuBLASLt/LtNvfp4Matmul/build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j32
    popd
}

main() {
    echo "Starting build process..."
    build_fp16_gemm
    build_mxfp8_gemm
    build_nvfp4_gemm
    echo "Build process completed."
}

main "$@"

# 
# Copyright (c) 2020, NVIDIA CORPORATION.  All rights reserved.
# 
# NVIDIA CORPORATION and its licensors retain all intellectual property
# and proprietary rights in and to this software, related documentation
# and any modifications thereto. Any use, reproduction, disclosure or
# distribution of this software and related documentation without an express
# license agreement from NVIDIA CORPORATION is strictly prohibited.
# 

cmake_minimum_required(VERSION 3.10.0)

project(sample_cublasLt_LtHSHgemmStridedBatchSimple LANGUAGES CXX CUDA)

set(SCOPE_VALUES 0.5 5)

foreach(SCOPE_VAL IN LISTS SCOPE_VALUES)
    set(target_name "${PROJECT_NAME}_Scope${SCOPE_VAL}")

    add_executable(${target_name}
        main.cpp
        ${PROJECT_NAME}.cu
    )

    target_include_directories(${target_name} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../Common
        ${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES}
    )

    target_compile_definitions(${target_name} PRIVATE SCOPE_MIN=-${SCOPE_VAL} SCOPE_MAX=${SCOPE_VAL})
    set_target_properties(${target_name} PROPERTIES CUDA_ARCHITECTURES "100a")

    set(CUDART_LIBRARY cudart)
    set(CUBLASLT_LIBRARY cublasLt)

    if(NOT WIN32)
        find_library(CUDART_LIBRARY cudart ${CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES})
        find_library(CUBLASLT_LIBRARY cublasLt ${CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES})
    endif()

    target_link_libraries(${target_name}
        ${CUDART_LIBRARY}
        ${CUBLASLT_LIBRARY}
    )
endforeach()
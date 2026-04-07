cmake_minimum_required(VERSION 3.22.1)
project(nextshell LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED NODE_HEADERS_DIR)
  message(FATAL_ERROR "NODE_HEADERS_DIR is required")
endif()

set(NODE_LIB_DIR "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}")

add_library(node SHARED IMPORTED)
set_target_properties(node PROPERTIES
  IMPORTED_LOCATION "${NODE_LIB_DIR}/libnode.so")

add_library(nextshell SHARED node_bridge.cpp)

target_include_directories(nextshell PRIVATE
  "${NODE_HEADERS_DIR}/include/node"
)

target_link_libraries(nextshell
  PRIVATE
    android
    log
    node
)

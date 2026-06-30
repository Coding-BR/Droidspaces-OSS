cmake_minimum_required(VERSION 3.18)
project(anland_consumer C)

add_library(anland_consumer SHARED
    native_consumer.c
    display_consumer.c
    socket_utils.c
)

target_include_directories(anland_consumer PRIVATE
    .
)

target_compile_options(anland_consumer PRIVATE -O3 -flto)
target_link_options(anland_consumer PRIVATE -flto -fuse-ld=lld)

target_link_libraries(anland_consumer
    android
    log
    dl
)

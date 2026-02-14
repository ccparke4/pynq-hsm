cmake_minimum_required(VERSION 3.20)
project(pynq_hs, C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

add_executable(test_trng
    sw/drivers/test_trng.cpp
)
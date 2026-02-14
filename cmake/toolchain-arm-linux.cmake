set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

# --- 1. Define Paths ---
# The root of the toolchain
set(ARM_TOOLCHAIN_PATH "C:/AMDDesignTools/2025.2/gnu/aarch32/nt/gcc-arm-linux-gnueabi")

# The specific folder you just found (The Sysroot)
set(ARM_SYSROOT "${ARM_TOOLCHAIN_PATH}/cortexa9t2hf-neon-amd-linux-gnueabi")

# --- 2. Force Compilers ---
# Standard Xilinx compiler names
set(CMAKE_C_COMPILER "${ARM_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-gcc.exe")
set(CMAKE_CXX_COMPILER "${ARM_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-g++.exe")

# --- 3. Set Sysroot ---
# This tells CMake where to look for headers and libraries
set(CMAKE_SYSROOT "${ARM_SYSROOT}")

# --- 4. Force Flags ---
# We manually add --sysroot to ensuring the linker sees it
set(COMMON_FLAGS "--sysroot=${ARM_SYSROOT}")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${COMMON_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${COMMON_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${COMMON_FLAGS}" CACHE STRING "" FORCE)

# --- 5. Search Modes ---
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
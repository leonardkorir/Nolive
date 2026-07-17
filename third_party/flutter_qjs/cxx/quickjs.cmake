cmake_minimum_required(VERSION 3.10)
set(CXX_LIB_DIR ${CMAKE_CURRENT_LIST_DIR})
set(CMAKE_C_STANDARD 11)

project(quickjs LANGUAGES C)

# quickjs
set(QUICK_JS_LIB_DIR ${CXX_LIB_DIR}/quickjs-ng)
file (STRINGS "${QUICK_JS_LIB_DIR}/VERSION" QUICKJS_VERSION)
add_library(quickjs STATIC
    ${QUICK_JS_LIB_DIR}/cutils.c
    ${QUICK_JS_LIB_DIR}/libregexp.c
    ${QUICK_JS_LIB_DIR}/libunicode.c
    ${QUICK_JS_LIB_DIR}/quickjs.c
    ${QUICK_JS_LIB_DIR}/libbf.c
)

target_compile_options(quickjs PRIVATE "-DCONFIG_VERSION=\"${QUICKJS_VERSION}\"")
target_compile_options(quickjs PRIVATE "-DDUMP_LEAKS")

# Keep QuickJS C API symbols local to the plugin DSO. Exporting JS_* globally
# collides with dart_quickjs (native assets) which builds a separate QuickJS
# and uses @Native FFI; PLT interposition then SIGSEGVs DouyuQuickJsSigner.
if(NOT MSVC)
    target_compile_options(quickjs PRIVATE "-fvisibility=hidden")
endif()

if(MSVC)
    # https://github.com/ekibun/flutter_qjs/issues/7
    target_compile_options(quickjs PRIVATE "/Oi-")
endif()
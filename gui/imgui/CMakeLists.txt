cmake_minimum_required(VERSION 3.20)
project(carto-canvas VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Dependencies
include(FetchContent)

FetchContent_Declare(
  imgui
  GIT_REPOSITORY https://github.com/ocornut/imgui.git
  GIT_TAG v1.91.8-docking
)
FetchContent_MakeAvailable(imgui)

find_package(glfw3 REQUIRED)
find_package(OpenGL REQUIRED)
find_library(SQLITE3_LIB sqlite3)

# ImGui library with GLFW + OpenGL3 backends
add_library(imgui_lib STATIC
  ${imgui_SOURCE_DIR}/imgui.cpp
  ${imgui_SOURCE_DIR}/imgui_demo.cpp
  ${imgui_SOURCE_DIR}/imgui_draw.cpp
  ${imgui_SOURCE_DIR}/imgui_tables.cpp
  ${imgui_SOURCE_DIR}/imgui_widgets.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp
)
target_include_directories(imgui_lib PUBLIC
  ${imgui_SOURCE_DIR}
  ${imgui_SOURCE_DIR}/backends
)
target_link_libraries(imgui_lib PUBLIC glfw OpenGL::GL)

# macOS frameworks
if(APPLE)
  target_link_libraries(imgui_lib PUBLIC "-framework Cocoa" "-framework IOKit")
endif()

# Carto Canvas executable
add_executable(carto-canvas
  src/main.cpp
  src/db_reader.cpp
  src/query_panel.cpp
  src/sql_inspector.cpp
  src/xref_explorer.cpp
  src/graph_panel.cpp
)
target_include_directories(carto-canvas PRIVATE include)
target_link_libraries(carto-canvas PRIVATE imgui_lib ${SQLITE3_LIB})

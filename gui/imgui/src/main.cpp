#define GL_SILENCE_DEPRECATION
#include "cartograph/app.h"

#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include <GLFW/glfw3.h>

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

static void GlfwErrorCallback(int error, const char* description) {
    std::cerr << "GLFW Error " << error << ": " << description << "\n";
}

static std::string FindDatabase(int argc, char* argv[]) {
    // Check command line argument
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: carto-canvas [options] [database.sqlite3]\n"
                      << "  --db PATH    Path to cartograph.sqlite3\n"
                      << "  --help       Show this help\n"
                      << "\nInteractive Cartograph code explorer using Dear ImGui.\n";
            std::exit(0);
        }
        if ((arg == "--db") && i + 1 < argc) {
            return argv[++i];
        }
        // Bare argument treated as db path
        if (arg[0] != '-') {
            return arg;
        }
    }

    // Search current directory and parent directories for .context/cartograph.sqlite3
    auto cwd = fs::current_path();
    for (auto dir = cwd; dir != dir.parent_path(); dir = dir.parent_path()) {
        auto candidate = dir / ".context" / "cartograph.sqlite3";
        if (fs::exists(candidate)) {
            return candidate.string();
        }
    }

    return "";
}

int main(int argc, char* argv[]) {
    AppState app;

    std::string db_path = FindDatabase(argc, argv);
    if (db_path.empty()) {
        std::cerr << "No cartograph.sqlite3 found. Pass --db <path> or run from a project root.\n";
        return 1;
    }

    if (!OpenDatabase(app, db_path)) {
        std::cerr << "Failed to open database: " << db_path << "\n";
        return 1;
    }

    // GLFW init
    glfwSetErrorCallback(GlfwErrorCallback);
    if (!glfwInit()) {
        std::cerr << "Failed to initialize GLFW\n";
        CloseDatabase(app);
        return 1;
    }

    // GL hints — OpenGL 3.2 Core Profile
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

    GLFWwindow* window = glfwCreateWindow(1440, 900, "Carto Canvas", nullptr, nullptr);
    if (!window) {
        std::cerr << "Failed to create GLFW window\n";
        glfwTerminate();
        CloseDatabase(app);
        return 1;
    }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    // ImGui init
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;

    // Catppuccin Mocha-ish dark style
    ImGui::StyleColorsDark();
    auto& style = ImGui::GetStyle();
    style.WindowRounding = 6.0f;
    style.FrameRounding = 4.0f;
    style.GrabRounding = 4.0f;
    style.TabRounding = 4.0f;
    style.WindowBorderSize = 1.0f;

    auto& colors = style.Colors;
    colors[ImGuiCol_WindowBg] = ImVec4(0.12f, 0.12f, 0.18f, 1.0f);
    colors[ImGuiCol_TitleBg] = ImVec4(0.08f, 0.08f, 0.12f, 1.0f);
    colors[ImGuiCol_TitleBgActive] = ImVec4(0.10f, 0.10f, 0.16f, 1.0f);
    colors[ImGuiCol_Tab] = ImVec4(0.12f, 0.12f, 0.18f, 1.0f);
    colors[ImGuiCol_TabSelected] = ImVec4(0.20f, 0.20f, 0.30f, 1.0f);
    colors[ImGuiCol_FrameBg] = ImVec4(0.15f, 0.15f, 0.22f, 1.0f);
    colors[ImGuiCol_Button] = ImVec4(0.20f, 0.20f, 0.30f, 1.0f);
    colors[ImGuiCol_ButtonHovered] = ImVec4(0.30f, 0.30f, 0.45f, 1.0f);

    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 150");

    // Main loop
    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        // Dockspace over viewport
        ImGui::DockSpaceOverViewport(0, ImGui::GetMainViewport());

        // Render panels
        RenderQueryPanel(app);
        RenderGraphPanel(app);
        RenderSQLInspector(app);
        RenderXRefExplorer(app);

        // Render
        ImGui::Render();
        int display_w, display_h;
        glfwGetFramebufferSize(window, &display_w, &display_h);
        glViewport(0, 0, display_w, display_h);
        glClearColor(0.07f, 0.07f, 0.11f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        glfwSwapBuffers(window);
    }

    // Cleanup
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
    CloseDatabase(app);
    return 0;
}

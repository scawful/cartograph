#include "cartograph/app.h"

#include <imgui.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <unordered_map>

// ---------------------------------------------------------------------------
// WorldToScreen: convert graph coordinates to screen pixel coordinates
// ---------------------------------------------------------------------------
static ImVec2 WorldToScreen(float wx, float wy, const AppState& app,
                            ImVec2 canvas_origin, ImVec2 canvas_size) {
    float cx = canvas_origin.x + canvas_size.x * 0.5f;
    float cy = canvas_origin.y + canvas_size.y * 0.5f;
    return ImVec2(cx + (wx + app.graph_offset_x) * app.graph_zoom,
                  cy + (wy + app.graph_offset_y) * app.graph_zoom);
}

// ---------------------------------------------------------------------------
// LoadGraphData: populate graph_nodes and graph_edges from the database
// ---------------------------------------------------------------------------
void LoadGraphData(AppState& app) {
    app.graph_nodes.clear();
    app.graph_edges.clear();
    app.graph_loaded = false;
    app.graph_simulating = false;
    app.graph_iterations = 0;
    app.graph_selected = -1;
    if (!app.db) return;

    // 1. Query symbols that have at least one internal xref
    std::string node_sql =
        "SELECT DISTINCT s.id, s.name, s.kind FROM symbols s "
        "INNER JOIN xrefs x ON (x.source_id = s.id OR x.target_id = s.id) "
        "WHERE s.project_id = ? AND x.target_id NOT LIKE 'external:%' "
        "LIMIT ?";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(app.db, node_sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) return;

    sqlite3_bind_text(stmt, 1, app.project_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, app.graph_max_nodes);

    std::unordered_map<std::string, int> id_to_index;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        GraphNode node;
        auto col_text = [&](int col) -> std::string {
            const char* txt =
                reinterpret_cast<const char*>(sqlite3_column_text(stmt, col));
            return txt ? txt : "";
        };
        node.id = col_text(0);
        node.name = col_text(1);
        node.kind = col_text(2);

        // Initialize position randomly in a circle of radius 300
        float angle =
            static_cast<float>(rand()) / static_cast<float>(RAND_MAX) * 6.2831853f;
        float radius =
            static_cast<float>(rand()) / static_cast<float>(RAND_MAX) * 300.0f;
        node.x = cosf(angle) * radius;
        node.y = sinf(angle) * radius;
        node.vx = 0.0f;
        node.vy = 0.0f;

        id_to_index[node.id] = static_cast<int>(app.graph_nodes.size());
        app.graph_nodes.push_back(std::move(node));
    }
    sqlite3_finalize(stmt);

    if (app.graph_nodes.empty()) return;

    // 2. Query edges (calls) between loaded nodes
    std::string edge_sql =
        "SELECT source_id, target_id FROM xrefs "
        "WHERE project_id = ? AND target_id NOT LIKE 'external:%' AND kind = 'calls'";

    stmt = nullptr;
    rc = sqlite3_prepare_v2(app.db, edge_sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) return;

    sqlite3_bind_text(stmt, 1, app.project_id.c_str(), -1, SQLITE_TRANSIENT);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char* src_txt =
            reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        const char* tgt_txt =
            reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1));
        if (!src_txt || !tgt_txt) continue;

        std::string src_id(src_txt);
        std::string tgt_id(tgt_txt);

        auto src_it = id_to_index.find(src_id);
        auto tgt_it = id_to_index.find(tgt_id);
        if (src_it != id_to_index.end() && tgt_it != id_to_index.end()) {
            GraphEdge edge;
            edge.source_idx = src_it->second;
            edge.target_idx = tgt_it->second;
            app.graph_edges.push_back(edge);
        }
    }
    sqlite3_finalize(stmt);

    app.graph_loaded = true;
    app.graph_simulating = true;
}

// ---------------------------------------------------------------------------
// SimulateGraph: spring-embedder force-directed layout
// ---------------------------------------------------------------------------
void SimulateGraph(AppState& app, int iterations) {
    int n = static_cast<int>(app.graph_nodes.size());
    if (n == 0) return;

    for (int iter = 0; iter < iterations; ++iter) {
        // 1. Repulsion between all node pairs
        for (int i = 0; i < n; ++i) {
            for (int j = i + 1; j < n; ++j) {
                float dx = app.graph_nodes[i].x - app.graph_nodes[j].x;
                float dy = app.graph_nodes[i].y - app.graph_nodes[j].y;
                float dist_sq = dx * dx + dy * dy + 1.0f;
                float force = 5000.0f / dist_sq;
                float dist = sqrtf(dist_sq);
                float fx = (dx / dist) * force;
                float fy = (dy / dist) * force;
                app.graph_nodes[i].vx += fx;
                app.graph_nodes[i].vy += fy;
                app.graph_nodes[j].vx -= fx;
                app.graph_nodes[j].vy -= fy;
            }
        }

        // 2. Attraction along edges
        for (const auto& edge : app.graph_edges) {
            auto& src = app.graph_nodes[edge.source_idx];
            auto& tgt = app.graph_nodes[edge.target_idx];
            float dx = tgt.x - src.x;
            float dy = tgt.y - src.y;
            float dist = sqrtf(dx * dx + dy * dy + 0.001f);
            float force = dist * 0.01f;
            float fx = (dx / dist) * force;
            float fy = (dy / dist) * force;
            src.vx += fx;
            src.vy += fy;
            tgt.vx -= fx;
            tgt.vy -= fy;
        }

        // 3. Centering force + 4. Damping + 5. Update positions
        for (auto& node : app.graph_nodes) {
            // Centering: gentle pull toward origin
            node.vx += -0.001f * node.x;
            node.vy += -0.001f * node.y;

            // Damping
            node.vx *= 0.9f;
            node.vy *= 0.9f;

            // Clamp velocity
            float speed = sqrtf(node.vx * node.vx + node.vy * node.vy);
            if (speed > 5.0f) {
                node.vx = (node.vx / speed) * 5.0f;
                node.vy = (node.vy / speed) * 5.0f;
            }

            // Update position
            node.x += node.vx;
            node.y += node.vy;
        }

        app.graph_iterations++;
    }
}

// ---------------------------------------------------------------------------
// NodeColor: return IM_COL32 based on symbol kind
// ---------------------------------------------------------------------------
static ImU32 NodeColor(const std::string& kind) {
    if (kind == "function")
        return IM_COL32(117, 171, 209, 255);  // blue
    if (kind == "class")
        return IM_COL32(199, 117, 209, 255);  // purple
    if (kind == "method")
        return IM_COL32(117, 209, 209, 255);  // cyan
    if (kind == "variable" || kind == "constant")
        return IM_COL32(209, 171, 117, 255);  // orange
    return IM_COL32(160, 160, 160, 255);       // gray default
}

// ---------------------------------------------------------------------------
// RenderGraphPanel: the main ImGui window for the graph visualizer
// ---------------------------------------------------------------------------
void RenderGraphPanel(AppState& app) {
    ImGui::Begin("Graph Visualizer");

    // ---- Toolbar ----
    if (ImGui::Button("Load")) {
        LoadGraphData(app);
    }
    ImGui::SameLine();

    if (app.graph_simulating) {
        if (ImGui::Button("Pause")) {
            app.graph_simulating = false;
        }
    } else {
        if (ImGui::Button("Simulate")) {
            app.graph_simulating = true;
        }
    }
    ImGui::SameLine();

    if (ImGui::Button("Reset")) {
        // Re-randomize positions, reset simulation
        for (auto& node : app.graph_nodes) {
            float angle =
                static_cast<float>(rand()) / static_cast<float>(RAND_MAX) * 6.2831853f;
            float radius =
                static_cast<float>(rand()) / static_cast<float>(RAND_MAX) * 300.0f;
            node.x = cosf(angle) * radius;
            node.y = sinf(angle) * radius;
            node.vx = 0.0f;
            node.vy = 0.0f;
        }
        app.graph_iterations = 0;
        app.graph_simulating = true;
    }
    ImGui::SameLine();

    ImGui::Text("Nodes: %d  Edges: %d  Iter: %d",
                static_cast<int>(app.graph_nodes.size()),
                static_cast<int>(app.graph_edges.size()),
                app.graph_iterations);

    ImGui::SameLine();
    ImGui::SetNextItemWidth(120.0f);
    ImGui::SliderFloat("Zoom", &app.graph_zoom, 0.1f, 3.0f, "%.2f");

    ImGui::SameLine();
    ImGui::SetNextItemWidth(80.0f);
    if (ImGui::InputInt("Max", &app.graph_max_nodes, 0, 0)) {
        if (app.graph_max_nodes < 50) app.graph_max_nodes = 50;
        if (app.graph_max_nodes > 1000) app.graph_max_nodes = 1000;
    }

    // ---- Simulation step ----
    if (app.graph_simulating && app.graph_loaded) {
        SimulateGraph(app, 1);
        if (app.graph_iterations >= 200) {
            app.graph_simulating = false;
        }
    }

    // ---- Canvas ----
    ImVec2 canvas_origin = ImGui::GetCursorScreenPos();
    ImVec2 canvas_size = ImGui::GetContentRegionAvail();
    if (canvas_size.x < 50.0f) canvas_size.x = 50.0f;
    if (canvas_size.y < 50.0f) canvas_size.y = 50.0f;

    ImDrawList* draw_list = ImGui::GetWindowDrawList();

    // Dark background rect
    draw_list->AddRectFilled(
        canvas_origin,
        ImVec2(canvas_origin.x + canvas_size.x, canvas_origin.y + canvas_size.y),
        IM_COL32(18, 18, 28, 255));

    // Invisible button to capture mouse input over the canvas area
    ImGui::InvisibleButton("graph_canvas", canvas_size,
                           ImGuiButtonFlags_MouseButtonLeft |
                           ImGuiButtonFlags_MouseButtonRight |
                           ImGuiButtonFlags_MouseButtonMiddle);
    bool canvas_hovered = ImGui::IsItemHovered();
    bool canvas_active = ImGui::IsItemActive();

    // ---- Mouse interaction ----
    ImGuiIO& io = ImGui::GetIO();

    // Panning with middle mouse or right mouse drag
    if (canvas_active &&
        (ImGui::IsMouseDragging(ImGuiMouseButton_Middle, 1.0f) ||
         ImGui::IsMouseDragging(ImGuiMouseButton_Right, 1.0f))) {
        ImVec2 delta = io.MouseDelta;
        app.graph_offset_x += delta.x / app.graph_zoom;
        app.graph_offset_y += delta.y / app.graph_zoom;
    }

    // Zoom with mouse wheel
    if (canvas_hovered && fabsf(io.MouseWheel) > 0.0f) {
        float zoom_delta = io.MouseWheel * 0.1f;
        app.graph_zoom += zoom_delta;
        if (app.graph_zoom < 0.1f) app.graph_zoom = 0.1f;
        if (app.graph_zoom > 3.0f) app.graph_zoom = 3.0f;
    }

    // Left click: select nearest node
    if (canvas_hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
        ImVec2 mouse_pos = io.MousePos;
        float best_dist_sq = 20.0f * 20.0f;  // 20px threshold
        int best_idx = -1;

        for (int i = 0; i < static_cast<int>(app.graph_nodes.size()); ++i) {
            ImVec2 screen_pos = WorldToScreen(app.graph_nodes[i].x,
                                              app.graph_nodes[i].y,
                                              app, canvas_origin, canvas_size);
            float dx = mouse_pos.x - screen_pos.x;
            float dy = mouse_pos.y - screen_pos.y;
            float dist_sq = dx * dx + dy * dy;
            if (dist_sq < best_dist_sq) {
                best_dist_sq = dist_sq;
                best_idx = i;
            }
        }

        app.graph_selected = best_idx;

        // Populate XRef Explorer with the selected symbol
        if (best_idx >= 0) {
            app.xref_symbol = app.graph_nodes[best_idx].name;
            FindCallers(app, app.xref_symbol);
            FindCallees(app, app.xref_symbol);
        }
    }

    // ---- Draw edges ----
    ImU32 edge_color = IM_COL32(100, 100, 140, 80);
    for (const auto& edge : app.graph_edges) {
        const auto& src = app.graph_nodes[edge.source_idx];
        const auto& tgt = app.graph_nodes[edge.target_idx];
        ImVec2 p1 = WorldToScreen(src.x, src.y, app, canvas_origin, canvas_size);
        ImVec2 p2 = WorldToScreen(tgt.x, tgt.y, app, canvas_origin, canvas_size);

        // Clip: skip edges entirely outside canvas (rough check)
        float min_x = canvas_origin.x;
        float max_x = canvas_origin.x + canvas_size.x;
        float min_y = canvas_origin.y;
        float max_y = canvas_origin.y + canvas_size.y;
        if ((p1.x < min_x && p2.x < min_x) || (p1.x > max_x && p2.x > max_x) ||
            (p1.y < min_y && p2.y < min_y) || (p1.y > max_y && p2.y > max_y))
            continue;

        draw_list->AddLine(p1, p2, edge_color, 1.0f);
    }

    // ---- Draw nodes ----
    float node_radius = 6.0f * app.graph_zoom;
    bool show_labels = app.graph_zoom > 0.4f;

    for (int i = 0; i < static_cast<int>(app.graph_nodes.size()); ++i) {
        const auto& node = app.graph_nodes[i];
        ImVec2 screen_pos =
            WorldToScreen(node.x, node.y, app, canvas_origin, canvas_size);

        // Skip nodes outside the canvas area (with some margin)
        float margin = node_radius + 20.0f;
        if (screen_pos.x < canvas_origin.x - margin ||
            screen_pos.x > canvas_origin.x + canvas_size.x + margin ||
            screen_pos.y < canvas_origin.y - margin ||
            screen_pos.y > canvas_origin.y + canvas_size.y + margin)
            continue;

        ImU32 color = NodeColor(node.kind);

        // Selected highlight ring
        if (i == app.graph_selected) {
            draw_list->AddCircle(screen_pos, node_radius + 4.0f,
                                 IM_COL32(255, 255, 100, 200), 0, 2.5f);
        }

        // Filled node circle
        draw_list->AddCircleFilled(screen_pos, node_radius, color);

        // Label (only if zoom is sufficient and node is visible)
        if (show_labels && !node.name.empty()) {
            draw_list->AddText(
                ImVec2(screen_pos.x + node_radius + 2.0f,
                       screen_pos.y - 6.0f),
                IM_COL32(220, 220, 220, 200),
                node.name.c_str());
        }
    }

    // ---- Info overlay for selected node ----
    if (app.graph_selected >= 0 &&
        app.graph_selected < static_cast<int>(app.graph_nodes.size())) {
        const auto& sel = app.graph_nodes[app.graph_selected];
        char info[512];
        snprintf(info, sizeof(info), "Selected: %s (%s)", sel.name.c_str(),
                 sel.kind.c_str());
        draw_list->AddText(
            ImVec2(canvas_origin.x + 8.0f, canvas_origin.y + 8.0f),
            IM_COL32(255, 255, 200, 230), info);
    }

    if (!app.graph_loaded) {
        const char* hint = "Click 'Load' to build the call graph";
        ImVec2 text_size = ImGui::CalcTextSize(hint);
        draw_list->AddText(
            ImVec2(canvas_origin.x + (canvas_size.x - text_size.x) * 0.5f,
                   canvas_origin.y + (canvas_size.y - text_size.y) * 0.5f),
            IM_COL32(160, 160, 180, 200), hint);
    }

    ImGui::End();
}

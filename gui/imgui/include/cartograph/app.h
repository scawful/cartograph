#pragma once

#include <string>
#include <vector>
#include <sqlite3.h>

struct GraphNode {
    std::string id;
    std::string name;
    std::string kind;
    float x, y;      // position
    float vx, vy;    // velocity
};

struct GraphEdge {
    int source_idx;   // index into graph_nodes
    int target_idx;
};

struct SymbolResult {
    std::string id;
    std::string name;
    std::string qualified_name;
    std::string kind;
    std::string file_path;
    int start_line;
    int end_line;
    std::string signature;
};

struct XrefResult {
    std::string source_name;
    std::string target_name;
    std::string kind;
    std::string file_path;
    int line;
};

struct AppState {
    std::string db_path;
    sqlite3* db = nullptr;
    std::string project_id;

    // Query panel
    char search_query[256] = "";
    int selected_kind = -1;  // -1 = all
    std::vector<SymbolResult> query_results;
    int selected_result = -1;

    // SQL Inspector
    char sql_query[4096] = "SELECT name, kind, start_line FROM symbols LIMIT 20";
    std::vector<std::string> sql_columns;
    std::vector<std::vector<std::string>> sql_rows;
    std::string sql_error;

    // XRef Explorer
    std::string xref_symbol;
    std::vector<XrefResult> callers;
    std::vector<XrefResult> callees;

    // Graph Visualizer
    std::vector<GraphNode> graph_nodes;
    std::vector<GraphEdge> graph_edges;
    bool graph_loaded = false;
    bool graph_simulating = false;
    int graph_iterations = 0;
    float graph_zoom = 1.0f;
    float graph_offset_x = 0.0f;
    float graph_offset_y = 0.0f;
    int graph_selected = -1;
    int graph_max_nodes = 200;
    char graph_focus[256] = "";
};

// Database operations
bool OpenDatabase(AppState& app, const std::string& path);
void CloseDatabase(AppState& app);
void SearchSymbols(AppState& app);
void ExecuteSQL(AppState& app);
void FindCallers(AppState& app, const std::string& symbol_name);
void FindCallees(AppState& app, const std::string& symbol_name);

// Graph operations
void LoadGraphData(AppState& app);
void SimulateGraph(AppState& app, int iterations = 1);

// Panel rendering
void RenderQueryPanel(AppState& app);
void RenderGraphPanel(AppState& app);
void RenderSQLInspector(AppState& app);
void RenderXRefExplorer(AppState& app);

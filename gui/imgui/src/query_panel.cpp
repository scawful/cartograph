#include "cartograph/app.h"

#include <imgui.h>

void RenderQueryPanel(AppState& app) {
    ImGui::Begin("Symbol Query");

    bool do_search = false;

    ImGui::Text("Search Symbols");
    ImGui::Separator();

    if (ImGui::InputText("Name", app.search_query, sizeof(app.search_query),
                         ImGuiInputTextFlags_EnterReturnsTrue)) {
        do_search = true;
    }

    static const char* kind_items[] = {"All", "function", "class", "method", "variable", "constant"};
    int combo_idx = app.selected_kind + 1;  // -1 maps to 0 ("All")
    if (ImGui::Combo("Kind", &combo_idx, kind_items, IM_ARRAYSIZE(kind_items))) {
        app.selected_kind = combo_idx - 1;
    }

    if (ImGui::Button("Search")) {
        do_search = true;
    }

    if (do_search) {
        SearchSymbols(app);
        app.selected_result = -1;
    }

    ImGui::Separator();
    ImGui::Text("Results: %zu", app.query_results.size());

    ImGui::BeginChild("ResultsList", ImVec2(0, 0), ImGuiChildFlags_Borders);
    for (int i = 0; i < static_cast<int>(app.query_results.size()); ++i) {
        auto& r = app.query_results[i];
        char label[512];
        snprintf(label, sizeof(label), "[%s] %s  (%s:%d)",
                 r.kind.c_str(), r.name.c_str(),
                 r.file_path.c_str(), r.start_line);

        bool selected = (i == app.selected_result);
        if (ImGui::Selectable(label, selected)) {
            app.selected_result = i;
            app.xref_symbol = r.name;
            FindCallers(app, r.name);
            FindCallees(app, r.name);
        }

        if (ImGui::IsItemHovered() && !r.signature.empty()) {
            ImGui::SetTooltip("%s", r.signature.c_str());
        }
    }
    ImGui::EndChild();

    ImGui::End();
}

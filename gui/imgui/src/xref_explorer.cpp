#include "cartograph/app.h"

#include <imgui.h>

void RenderXRefExplorer(AppState& app) {
    ImGui::Begin("XRef Explorer");

    if (app.xref_symbol.empty()) {
        ImGui::TextDisabled("Select a symbol from the Query panel to explore cross-references.");
        ImGui::End();
        return;
    }

    ImGui::Text("Symbol: %s", app.xref_symbol.c_str());
    ImGui::Separator();

    if (ImGui::CollapsingHeader("Callers", ImGuiTreeNodeFlags_DefaultOpen)) {
        if (app.callers.empty()) {
            ImGui::TextDisabled("  (none)");
        }
        for (auto& xr : app.callers) {
            char label[512];
            snprintf(label, sizeof(label), "%s  [%s]  %s:%d",
                     xr.source_name.c_str(), xr.kind.c_str(),
                     xr.file_path.c_str(), xr.line);
            if (ImGui::Selectable(label)) {
                app.xref_symbol = xr.source_name;
                FindCallers(app, xr.source_name);
                FindCallees(app, xr.source_name);
            }
        }
    }

    if (ImGui::CollapsingHeader("Callees", ImGuiTreeNodeFlags_DefaultOpen)) {
        if (app.callees.empty()) {
            ImGui::TextDisabled("  (none)");
        }
        for (auto& xr : app.callees) {
            char label[512];
            snprintf(label, sizeof(label), "%s  [%s]  %s:%d",
                     xr.target_name.c_str(), xr.kind.c_str(),
                     xr.file_path.c_str(), xr.line);
            if (ImGui::Selectable(label)) {
                app.xref_symbol = xr.target_name;
                FindCallers(app, xr.target_name);
                FindCallees(app, xr.target_name);
            }
        }
    }

    ImGui::End();
}

#include "cartograph/app.h"

#include <imgui.h>

void RenderSQLInspector(AppState& app) {
    ImGui::Begin("SQL Inspector");

    ImGui::Text("Raw SQL Query");
    ImGui::Separator();

    ImGui::InputTextMultiline("##sql", app.sql_query, sizeof(app.sql_query),
                              ImVec2(-1.0f, ImGui::GetTextLineHeight() * 6));

    if (ImGui::Button("Execute")) {
        ExecuteSQL(app);
    }

    if (!app.sql_error.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.4f, 0.4f, 1.0f));
        ImGui::TextWrapped("Error: %s", app.sql_error.c_str());
        ImGui::PopStyleColor();
    }

    ImGui::Separator();

    if (!app.sql_columns.empty()) {
        ImGui::Text("Rows: %zu", app.sql_rows.size());

        int col_count = static_cast<int>(app.sql_columns.size());
        if (ImGui::BeginTable("SQLResults", col_count,
                              ImGuiTableFlags_Borders | ImGuiTableFlags_RowBg |
                              ImGuiTableFlags_Resizable | ImGuiTableFlags_ScrollY,
                              ImVec2(0, 0))) {

            for (auto& col : app.sql_columns) {
                ImGui::TableSetupColumn(col.c_str());
            }
            ImGui::TableHeadersRow();

            for (auto& row : app.sql_rows) {
                ImGui::TableNextRow();
                for (int c = 0; c < col_count && c < static_cast<int>(row.size()); ++c) {
                    ImGui::TableSetColumnIndex(c);
                    ImGui::TextUnformatted(row[c].c_str());
                }
            }

            ImGui::EndTable();
        }
    }

    ImGui::End();
}

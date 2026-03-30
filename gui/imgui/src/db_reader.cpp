#include "cartograph/app.h"

#include <iostream>

bool OpenDatabase(AppState& app, const std::string& path) {
    if (app.db) {
        sqlite3_close(app.db);
        app.db = nullptr;
    }

    int flags = SQLITE_OPEN_READONLY;
    int rc = sqlite3_open_v2(path.c_str(), &app.db, flags, nullptr);
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to open database: " << sqlite3_errmsg(app.db) << "\n";
        sqlite3_close(app.db);
        app.db = nullptr;
        return false;
    }

    app.db_path = path;

    // Find the first project_id
    sqlite3_stmt* stmt = nullptr;
    rc = sqlite3_prepare_v2(app.db, "SELECT id FROM projects LIMIT 1", -1, &stmt, nullptr);
    if (rc == SQLITE_OK && sqlite3_step(stmt) == SQLITE_ROW) {
        app.project_id = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
    }
    if (stmt) sqlite3_finalize(stmt);

    std::cout << "Opened database: " << path << "\n";
    if (!app.project_id.empty()) {
        std::cout << "Project ID: " << app.project_id << "\n";
    }

    return true;
}

void CloseDatabase(AppState& app) {
    if (app.db) {
        sqlite3_close(app.db);
        app.db = nullptr;
    }
    app.db_path.clear();
    app.project_id.clear();
}

void SearchSymbols(AppState& app) {
    app.query_results.clear();
    if (!app.db) return;

    std::string sql = "SELECT id, name, qualified_name, kind, file_path, start_line, end_line, signature "
                      "FROM symbols WHERE name LIKE ?";

    static const char* kinds[] = {"function", "class", "method", "variable", "constant"};
    if (app.selected_kind >= 0 && app.selected_kind < 5) {
        sql += " AND kind = ?";
    }
    sql += " ORDER BY name LIMIT 200";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(app.db, sql.c_str(), -1, &stmt, nullptr);
    if (rc != SQLITE_OK) return;

    std::string pattern = std::string("%") + app.search_query + "%";
    sqlite3_bind_text(stmt, 1, pattern.c_str(), -1, SQLITE_TRANSIENT);

    if (app.selected_kind >= 0 && app.selected_kind < 5) {
        sqlite3_bind_text(stmt, 2, kinds[app.selected_kind], -1, SQLITE_STATIC);
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        SymbolResult r;
        auto col_text = [&](int col) -> std::string {
            const char* txt = reinterpret_cast<const char*>(sqlite3_column_text(stmt, col));
            return txt ? txt : "";
        };
        r.id = col_text(0);
        r.name = col_text(1);
        r.qualified_name = col_text(2);
        r.kind = col_text(3);
        r.file_path = col_text(4);
        r.start_line = sqlite3_column_int(stmt, 5);
        r.end_line = sqlite3_column_int(stmt, 6);
        r.signature = col_text(7);
        app.query_results.push_back(std::move(r));
    }

    sqlite3_finalize(stmt);
}

void ExecuteSQL(AppState& app) {
    app.sql_columns.clear();
    app.sql_rows.clear();
    app.sql_error.clear();
    if (!app.db) {
        app.sql_error = "No database open";
        return;
    }

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(app.db, app.sql_query, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        app.sql_error = sqlite3_errmsg(app.db);
        return;
    }

    int col_count = sqlite3_column_count(stmt);
    for (int i = 0; i < col_count; ++i) {
        const char* name = sqlite3_column_name(stmt, i);
        app.sql_columns.push_back(name ? name : "?");
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        std::vector<std::string> row;
        for (int i = 0; i < col_count; ++i) {
            const char* val = reinterpret_cast<const char*>(sqlite3_column_text(stmt, i));
            row.push_back(val ? val : "(null)");
        }
        app.sql_rows.push_back(std::move(row));
    }

    sqlite3_finalize(stmt);
}

void FindCallers(AppState& app, const std::string& symbol_name) {
    app.callers.clear();
    if (!app.db || symbol_name.empty()) return;

    const char* sql =
        "SELECT x.source_symbol_id, x.target_symbol_id, x.kind, x.file_path, x.line, "
        "       s.name AS source_name, t.name AS target_name "
        "FROM xrefs x "
        "LEFT JOIN symbols s ON x.source_symbol_id = s.id "
        "LEFT JOIN symbols t ON x.target_symbol_id = t.id "
        "WHERE t.name = ? "
        "ORDER BY s.name LIMIT 100";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(app.db, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) return;

    sqlite3_bind_text(stmt, 1, symbol_name.c_str(), -1, SQLITE_TRANSIENT);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        XrefResult r;
        auto col_text = [&](int col) -> std::string {
            const char* txt = reinterpret_cast<const char*>(sqlite3_column_text(stmt, col));
            return txt ? txt : "";
        };
        r.source_name = col_text(5);
        r.target_name = col_text(6);
        r.kind = col_text(2);
        r.file_path = col_text(3);
        r.line = sqlite3_column_int(stmt, 4);
        app.callers.push_back(std::move(r));
    }

    sqlite3_finalize(stmt);
}

void FindCallees(AppState& app, const std::string& symbol_name) {
    app.callees.clear();
    if (!app.db || symbol_name.empty()) return;

    const char* sql =
        "SELECT x.source_symbol_id, x.target_symbol_id, x.kind, x.file_path, x.line, "
        "       s.name AS source_name, t.name AS target_name "
        "FROM xrefs x "
        "LEFT JOIN symbols s ON x.source_symbol_id = s.id "
        "LEFT JOIN symbols t ON x.target_symbol_id = t.id "
        "WHERE s.name = ? "
        "ORDER BY t.name LIMIT 100";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(app.db, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) return;

    sqlite3_bind_text(stmt, 1, symbol_name.c_str(), -1, SQLITE_TRANSIENT);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        XrefResult r;
        auto col_text = [&](int col) -> std::string {
            const char* txt = reinterpret_cast<const char*>(sqlite3_column_text(stmt, col));
            return txt ? txt : "";
        };
        r.source_name = col_text(5);
        r.target_name = col_text(6);
        r.kind = col_text(2);
        r.file_path = col_text(3);
        r.line = sqlite3_column_int(stmt, 4);
        app.callees.push_back(std::move(r));
    }

    sqlite3_finalize(stmt);
}

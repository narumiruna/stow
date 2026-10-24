fn main() {
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "desktop_status",
            "search_items",
            "get_item",
            "create_item",
            "update_item",
            "apply_item_command",
            "rebuild_search",
            "close_preview",
        ]),
    ))
    .expect("Tauri application build failed");
}

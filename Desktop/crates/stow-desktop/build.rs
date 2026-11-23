fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        build_swift_bridge();
    }
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

fn swift(arguments: &[&str]) -> std::process::Output {
    let output = std::process::Command::new("xcrun")
        .arg("swift")
        .args(arguments)
        .env("MACOSX_DEPLOYMENT_TARGET", "14.0")
        .output()
        .expect("The macOS bridge requires Xcode and xcrun swift");
    assert!(
        output.status.success(),
        "Swift bridge command failed ({}):\n{}\n{}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

fn build_swift_bridge() {
    use std::{env, path::PathBuf};
    assert_eq!(
        env::var("HOST").unwrap(),
        env::var("TARGET").unwrap(),
        "The preview Swift bridge requires a native macOS build"
    );
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let desktop = manifest.join("../..");
    let package = desktop.join("native/macos").canonicalize().unwrap();
    let scratch = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("swift");
    for path in [
        package.join("Package.swift"),
        package.join("Sources"),
        desktop.join("../Packages/StowCore/Package.swift"),
        desktop.join("../Packages/StowCore/Sources"),
    ] {
        println!("cargo:rerun-if-changed={}", path.display());
    }
    println!("cargo:rerun-if-env-changed=DEVELOPER_DIR");
    let package = package.to_str().unwrap();
    let scratch = scratch.to_str().unwrap();
    swift(&[
        "build",
        "--package-path",
        package,
        "--scratch-path",
        scratch,
        "--configuration",
        "release",
        "--product",
        "StowDesktopBridge",
    ]);
    let output = swift(&[
        "build",
        "--package-path",
        package,
        "--scratch-path",
        scratch,
        "--configuration",
        "release",
        "--show-bin-path",
    ]);
    let bin = String::from_utf8(output.stdout).unwrap();
    println!("cargo:rustc-link-search=native={}", bin.trim());
    println!("cargo:rustc-link-lib=static=StowDesktopBridge");
    let output = swift(&["-print-target-info"]);
    let info: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    for path in info["paths"]["runtimeLibraryPaths"].as_array().unwrap() {
        println!("cargo:rustc-link-search=native={}", path.as_str().unwrap());
    }
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
    for framework in [
        "Foundation",
        "SwiftData",
        "CoreFoundation",
        "CryptoKit",
        "Security",
        "ImageIO",
        "UniformTypeIdentifiers",
    ] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
    for library in ["swiftCore", "swift_Concurrency", "sqlite3"] {
        println!("cargo:rustc-link-lib={library}");
    }
}

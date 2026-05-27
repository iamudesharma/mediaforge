// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "integration_test", path: "../.packages/integration_test"),
        .package(name: "camera_avfoundation", path: "../.packages/camera_avfoundation-0.9.23+2"),
        .package(name: "image_picker_ios", path: "../.packages/image_picker_ios-0.8.13+6"),
        .package(name: "gal", path: "../.packages/gal-2.3.2"),
        .package(name: "file_selector_ios", path: "../.packages/file_selector_ios-0.5.3+5"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "integration-test", package: "integration_test"),
                .product(name: "camera-avfoundation", package: "camera_avfoundation"),
                .product(name: "image-picker-ios", package: "image_picker_ios"),
                .product(name: "gal", package: "gal"),
                .product(name: "file-selector-ios", package: "file_selector_ios"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)

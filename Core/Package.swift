// swift-tools-version:5.9
import PackageDescription

// 气动一维热力计算核心包。零第三方依赖：纯 Foundation 数值计算，Linux 可编译——
// 单测在 fun2 公开仓的 ubuntu runner 上跑（1× 分钟），macOS runner 只用来出包。
// golden 对照数据放测试资源 Fixtures/，测试经 Bundle.module 读取。
let package = Package(
    name: "Core1D",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Core1D", targets: ["Core1D"]),
    ],
    targets: [
        .target(name: "Core1D"),
        .testTarget(
            name: "Core1DTests",
            dependencies: ["Core1D"],
            resources: [
                // golden.json 随 Fixtures/ 整目录进测试资源
                .copy("Fixtures"),
            ]
        ),
    ]
)

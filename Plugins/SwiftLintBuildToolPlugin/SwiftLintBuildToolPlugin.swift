import Foundation
import PackagePlugin

@main
struct SwiftLintBuildToolPlugin {
    /// Creates a swift lint command that will get run before the build process.
    /// - Parameters:
    ///   - executable: The executable to run.
    ///   - swiftFiles: The swift files to lint.
    ///   - environment: The custom workspace environment to run the subprocess.
    ///   - workingDirectory: The plugin work directory.
    /// - Returns: The prebuild command.
    func makePrebuildCommand(
        executable: PluginContext.Tool,
        swiftFiles: [Path],
        environment: [String: String],
        workingDirectory: Path
    ) throws -> [Command] {
        // Don't lint anything if there are no Swift source files in this target.
        guard !swiftFiles.isEmpty else { return [] }
        
        let arguments: [String] = [
            "lint",
            "--quiet",
            // We always pass all of the Swift source files in the target to the tool,
            // so we need to ensure that any exclusion rules in the configuration are
            // respected.
            "--force-exclude"
        ]
        
        let cachePath = workingDirectory.appending("Cache")
        
        // Create cache directory.
        try FileManager.default.createDirectory(
            atPath: cachePath.string,
            withIntermediateDirectories: true
        )
        
        let cacheArguments = ["--cache-path", "\(cachePath)"]
        
        let outputPath = workingDirectory.appending("Output")
        
        // Create output directory.
        try FileManager.default.createDirectory(
            atPath: outputPath.string,
            withIntermediateDirectories: true
        )
        
        return [
            .prebuildCommand(
                displayName: "SwiftLint",
                executable: executable.path,
                arguments: arguments + cacheArguments + swiftFiles.map(\.string),
                environment: environment,
                outputFilesDirectory: outputPath
            )
        ]
    }
}

// This is the build tool plugin that will be run in swift packages.
extension SwiftLintBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let swiftFiles = (target as? SourceModuleTarget)?
            .sourceFiles(withSuffix: "swift")
            .map(\.path)
        ?? []
        
        return try makePrebuildCommand(
            executable: context.tool(named: .swiftlintExecutableName),
            swiftFiles: swiftFiles,
            environment: [.workspaceDirectoryKey: "\(context.package.directory)"], // The `BUILD_WORKSPACE_DIRECTORY` environment variable controls SwiftLint's working directory.
            workingDirectory: context.pluginWorkDirectory
        )
    }
}

#if canImport(XcodeProjectPlugin)

import XcodeProjectPlugin

// This is the build tool plugin will be run in Xcode projects.
extension SwiftLintBuildToolPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        let swiftFiles = target
            .inputFiles
            .filter { $0.type == .source && $0.path.extension == "swift" }
            .map(\.path)
        
        return try makePrebuildCommand(
            executable: context.tool(named: .swiftlintExecutableName),
            swiftFiles: swiftFiles,
            environment: [.workspaceDirectoryKey: "\(context.xcodeProject.directory)"], // The `BUILD_WORKSPACE_DIRECTORY` environment variable controls SwiftLint's working directory.
            workingDirectory: context.pluginWorkDirectory
        )
    }
}

#endif

private extension String {
    /// The name of the SwiftLint executable that will get run.
    static let swiftlintExecutableName = "swiftlint"
    
    /// The workspace directory key that should be used for the custom environment.
    static let workspaceDirectoryKey = "BUILD_WORKSPACE_DIRECTORY"
}

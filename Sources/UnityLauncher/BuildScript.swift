import Foundation

/// Signed Android builds: Unity never saves keystore passwords and `unity build` only accepts them with
/// `--execute-method`, so the launcher adds a tiny build method to the project and hands it the profile
/// and passwords through environment variables (never argv, never disk).
enum BuildScript {
    static let relativePath = "Assets/Editor/UnityLauncherBuild.cs"
    static let method = "UnityLauncherBuild.Build"

    enum Status: Equatable { case missing, current, outdated }

    static func status(project: URL) -> Status {
        guard let text = try? String(contentsOf: project.appendingPathComponent(relativePath), encoding: .utf8) else { return .missing }
        return text == source ? .current : .outdated
    }

    static func install(project: URL) throws {
        let url = project.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    static func arguments(project: String, target: BuildTarget, output: String, allowDirty: Bool) -> [String] {
        ["build", project, "--output-path", output, "--target", target.rawValue, "--execute-method", method]
            + (allowDirty ? ["--allow-dirty-build"] : [])
    }

    static func environment(profile: String, keystorePassword: String = "", aliasPassword: String = "",
                            iosSimulator: Bool = false) -> [String: String] {
        var env = ["UNITY_LAUNCHER_PROFILE": profile]
        if !keystorePassword.isEmpty { env["UNITY_LAUNCHER_KEYSTORE_PASS"] = keystorePassword }
        if !aliasPassword.isEmpty { env["UNITY_LAUNCHER_KEYALIAS_PASS"] = aliasPassword }
        if iosSimulator { env["UNITY_LAUNCHER_IOS_SDK"] = "simulator" }
        return env
    }

    static let source = """
    // Added by Unity Launcher. Safe to commit; contains no secrets.
    // Builds a Build Profile in batch mode and applies Android keystore passwords from environment
    // variables: Unity never saves those passwords and `unity build --profile` can't pass them.
    // Run as: unity build <project> --target Android --execute-method UnityLauncherBuild.Build --output-path <file>
    #nullable enable
    using System;
    using UnityEditor;
    using UnityEditor.Build.Profile;
    using UnityEditor.Build.Reporting;

    public static class UnityLauncherBuild
    {
        public static void Build()
        {
            string? profilePath = Environment.GetEnvironmentVariable("UNITY_LAUNCHER_PROFILE");
            string? output = Argument("-buildOutput");
            BuildProfile? profile = AssetDatabase.LoadAssetAtPath<BuildProfile>(profilePath);
            if (profile == null) throw new Exception("Unity Launcher: Build Profile not found: " + profilePath);
            if (string.IsNullOrEmpty(output)) throw new Exception("Unity Launcher: missing -buildOutput");

            // Keystore passwords belong to the active player settings, so activate the profile first.
            BuildProfile.SetActiveBuildProfile(profile);
            string? keystorePass = Environment.GetEnvironmentVariable("UNITY_LAUNCHER_KEYSTORE_PASS");
            if (!string.IsNullOrEmpty(keystorePass))
            {
                string? aliasPass = Environment.GetEnvironmentVariable("UNITY_LAUNCHER_KEYALIAS_PASS");
                PlayerSettings.Android.keystorePass = keystorePass;
                PlayerSettings.Android.keyaliasPass = string.IsNullOrEmpty(aliasPass) ? keystorePass : aliasPass;
            }

            // iOS Simulator builds switch the SDK for this build only, then put the profile back.
            // Arm64 too: Unity defaults simulator builds to x86_64, which Apple-silicon simulators can't run.
            iOSSdkVersion? previousSdk = null;
            AppleMobileArchitectureSimulator? previousArch = null;
            if (Environment.GetEnvironmentVariable("UNITY_LAUNCHER_IOS_SDK") == "simulator")
            {
                previousSdk = PlayerSettings.iOS.sdkVersion;
                previousArch = PlayerSettings.iOS.simulatorSdkArchitecture;
                PlayerSettings.iOS.sdkVersion = iOSSdkVersion.SimulatorSDK;
                PlayerSettings.iOS.simulatorSdkArchitecture = AppleMobileArchitectureSimulator.ARM64;
            }
            try
            {
                BuildReport report = BuildPipeline.BuildPlayer(new BuildPlayerWithProfileOptions
                {
                    buildProfile = profile,
                    locationPathName = output,
                    options = BuildOptions.None,
                });
                if (report.summary.result != BuildResult.Succeeded)
                    throw new Exception("Unity Launcher: build " + report.summary.result);
            }
            finally
            {
                if (previousSdk.HasValue) PlayerSettings.iOS.sdkVersion = previousSdk.Value;
                if (previousArch.HasValue) PlayerSettings.iOS.simulatorSdkArchitecture = previousArch.Value;
            }
        }

        static string? Argument(string name)
        {
            string[] args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, name);
            return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
        }
    }

    """
}

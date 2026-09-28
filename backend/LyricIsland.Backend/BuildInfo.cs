using System.Reflection;

namespace LyricIsland.Backend;

public static class BuildInfo
{
    public static string Version { get; } = typeof(BuildInfo).Assembly
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()!.InformationalVersion;
}

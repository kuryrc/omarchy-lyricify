using System.Text;
using LyricIsland.Backend;

Console.InputEncoding = Encoding.UTF8;
Console.OutputEncoding = new UTF8Encoding(false);
if (args.Length != 1 || args[0] != "--stdio")
{
    Console.Error.WriteLine("Usage: LyricIsland.Backend --stdio");
    Environment.ExitCode = 2;
    return;
}
try { await LyricIsland.Backend.Protocol.ProtocolHost.RunAsync(); }
catch (Exception error) when (error is not OutOfMemoryException)
{
    // Never print paths, metadata or serialized user data on startup failure.
    Console.Error.WriteLine(error is RequestError re ? re.Code : "backend_start_failed");
    Environment.ExitCode = 1;
}

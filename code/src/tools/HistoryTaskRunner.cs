using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

internal static class HistoryTaskRunner
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length != 2 || !File.Exists(args[0]) || !Directory.Exists(args[1]))
                throw new ArgumentException("Expected an existing PowerShell script and working directory.");

            var start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \""
                    + args[0] + "\"",
                WorkingDirectory = args[1],
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var process = Process.Start(start))
            {
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                Task.WaitAll(output, error);
                if (process.ExitCode != 0)
                    Log("Exit " + process.ExitCode + ": " + error.Result + output.Result);
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Log(ex.ToString());
            return 1;
        }
    }

    private static void Log(string message)
    {
        try
        {
            File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launcher-errors.log"),
                DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine);
        }
        catch { /* Exit status still reports failure if logging is unavailable. */ }
    }
}

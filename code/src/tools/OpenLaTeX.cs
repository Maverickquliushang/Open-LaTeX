using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

internal static class OpenLaTeX
{
    [STAThread]
    private static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        bool diagnose = args.Length == 1 && args[0] == "--diagnose";
        if (args.Length != 0 && !diagnose) return 2;
        try
        {
            string script = Path.Combine(root, "Open-LaTeX.cmd");
            if (!File.Exists(script))
                throw new FileNotFoundException("Open-LaTeX.cmd was not found beside the launcher.", script);
            var start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe"),
                Arguments = "/d /s /c \"\"" + script + "\"" + (diagnose ? " -Diagnose" : "") + "\"",
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            start.EnvironmentVariables["LATEX_NO_WINDOW"] = "1";
            using (var process = Process.Start(start))
            {
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                Task.WaitAll(output, error);
                if (diagnose) { Console.Write(output.Result); Console.Error.Write(error.Result); }
                if (process.ExitCode != 0 && !diagnose)
                    ShowError(root, "启动失败，请确认 Docker Desktop 已运行，且已安装 VS Code。\r\n\r\n"
                        + error.Result + output.Result);
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            if (diagnose) Console.Error.WriteLine(ex.Message); else ShowError(root, ex.Message);
            return 1;
        }
    }

    private static void ShowError(string root, string message)
    {
        try
        {
            string logDir = Path.Combine(root, ".tmp", "open-latex");
            Directory.CreateDirectory(logDir);
            File.WriteAllText(Path.Combine(logDir, "last-error.log"),
                DateTimeOffset.Now.ToString("o") + Environment.NewLine + message);
        }
        catch { }
        MessageBox.Show(message.Length > 3000 ? message.Substring(0, 3000) : message,
            "Open LaTeX", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}

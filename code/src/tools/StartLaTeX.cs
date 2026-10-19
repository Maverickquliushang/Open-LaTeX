using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

internal interface IStartupHost
{
    string ProbeEngine();
    void StartDesktop();
    void OpenWorkspace();
    void Pause();
    TimeSpan Elapsed { get; }
}

internal static class StartupFlow
{
    internal static void Run(IStartupHost host, Action<string> status, CancellationToken cancel, TimeSpan timeout)
    {
        status("正在检查 Docker…");
        string engine = host.ProbeEngine();
        if (engine == "windows") throw new InvalidOperationException("Docker 当前使用 Windows 容器，请切换到 Linux 容器后重试。");
        if (engine != "linux")
        {
            status("正在启动 Docker Desktop…");
            host.StartDesktop();
            TimeSpan began = host.Elapsed;
            while (true)
            {
                cancel.ThrowIfCancellationRequested();
                status("正在等待 Docker 就绪…首次启动可能需要一两分钟。");
                engine = host.ProbeEngine();
                if (engine == "linux") break;
                if (engine == "windows") throw new InvalidOperationException("Docker 当前使用 Windows 容器，请切换到 Linux 容器后重试。");
                if (host.Elapsed - began >= timeout) throw new TimeoutException("等待 Docker 超时。请打开 Docker Desktop 查看是否有更新、首次设置或错误提示，再重试。");
                host.Pause();
            }
        }
        cancel.ThrowIfCancellationRequested();
        status("正在启动配置的容器、论文历史，并请求 VS Code 连接…");
        host.OpenWorkspace();
        status("已发送工作区打开请求；远程连接和扩展激活尚未核验。");
    }
}

internal sealed class StartupHost : IStartupHost
{
    private readonly string root;
    private readonly string docker;
    private readonly CancellationToken cancel;
    private readonly Stopwatch watch = Stopwatch.StartNew();
    public TimeSpan Elapsed { get { return watch.Elapsed; } }

    internal StartupHost(string directory, CancellationToken token)
    {
        root = directory; cancel = token;
        if (File.Exists(Path.Combine(root, ".latex-tools", ".deployment-in-progress.json")))
            throw new InvalidOperationException("正在更新运行组件，请等待部署完成后再启动。");
        if (!File.Exists(Path.Combine(root, "Open-LaTeX.exe")))
            throw new FileNotFoundException("请把 Start-LaTeX.exe 放在 Open-LaTeX.exe 所在的论文目录中。");
        docker = FindDocker();
    }

    private static string FindDocker()
    {
        foreach (string entry in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            try
            {
                string candidate = Path.Combine(entry.Trim().Trim('"'), "docker.exe");
                if (Path.IsPathRooted(candidate) && File.Exists(candidate)) return candidate;
            }
            catch (ArgumentException) { }
        }
        string fallback = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Docker", "Docker", "resources", "bin", "docker.exe");
        if (File.Exists(fallback)) return fallback;
        throw new FileNotFoundException("没有找到 Docker Desktop 的 docker.exe，请先安装 Docker Desktop。");
    }

    private sealed class Result
    {
        internal int Code;
        internal string Output;
        internal string Error;
    }

    private Result Run(string exe, string arguments, int timeoutSeconds)
    {
        cancel.ThrowIfCancellationRequested();
        var start = new ProcessStartInfo {
            FileName = exe, Arguments = arguments, WorkingDirectory = root,
            UseShellExecute = false, CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true, RedirectStandardError = true
        };
        using (var process = Process.Start(start))
        {
            Task<string> stdout = process.StandardOutput.ReadToEndAsync();
            Task<string> stderr = process.StandardError.ReadToEndAsync();
            var timer = Stopwatch.StartNew();
            try
            {
                while (!process.WaitForExit(200))
                {
                    cancel.ThrowIfCancellationRequested();
                    if (timer.Elapsed.TotalSeconds >= timeoutSeconds)
                        throw new TimeoutException(Path.GetFileName(exe) + " 未在规定时间内响应。");
                }
                // Desktop can leave stdout handles inherited by its background processes.
                // The CLI has exited; do not wait indefinitely for those processes to close.
                Task.WaitAll(new Task[] { stdout, stderr }, 2000);
                return new Result { Code = process.ExitCode,
                    Output = stdout.Status == TaskStatus.RanToCompletion ? stdout.Result : "",
                    Error = stderr.Status == TaskStatus.RanToCompletion ? stderr.Result : "" };
            }
            catch
            {
                try { if (!process.HasExited) process.Kill(); } catch { }
                throw;
            }
        }
    }

    public string ProbeEngine()
    {
        try
        {
            Result result = Run(docker, "info --format \"{{.OSType}}\"", 8);
            return result.Code == 0 ? result.Output.Trim().ToLowerInvariant() : "";
        }
        catch (TimeoutException) { return ""; }
    }

    public void StartDesktop()
    {
        string installation = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(docker), "..", ".."));
        foreach (string candidate in new[] {
            Path.Combine(installation,"frontend","Docker Desktop.exe"),
            Path.Combine(installation,"Docker Desktop.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Docker","Docker","frontend","Docker Desktop.exe")
        })
        {
            if (!File.Exists(candidate)) continue;
            // Launch the GUI independently: Desktop must outlive the short-lived CLI.
            using (Process desktop = Process.Start(new ProcessStartInfo {
                FileName = candidate, WorkingDirectory = Path.GetDirectoryName(candidate),
                UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden
            })) { }
            return;
        }
        Result result = Run(docker, "desktop start --detach", 45);
        if (result.Code != 0)
            throw new InvalidOperationException("无法自动启动 Docker Desktop。\r\n" + result.Error + result.Output);
    }

    public void OpenWorkspace()
    {
        Result result = Run(Path.Combine(root, "Open-LaTeX.exe"), "", 120);
        if (result.Code != 0)
            throw new InvalidOperationException("Docker 已就绪，但论文工作区启动失败。请查看 .tmp/open-latex/last-error.log。");
    }

    public void Pause()
    {
        if (cancel.WaitHandle.WaitOne(2000)) cancel.ThrowIfCancellationRequested();
    }
}

internal sealed class StartupWindow : Form
{
    private readonly string root = AppDomain.CurrentDomain.BaseDirectory;
    private readonly CancellationTokenSource cancellation = new CancellationTokenSource();
    private readonly Label status;
    private bool finished;
    internal int ExitCode = 0;

    internal StartupWindow()
    {
        Text = "启动 LaTeX";
        ClientSize = new Size(490, 170);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        Font = new Font("Microsoft YaHei UI", 9F);
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        var title = new Label { Text = "LaTeX 一键启动", Location = new Point(22,18), AutoSize = true, Font = new Font(Font.FontFamily,14F,FontStyle.Bold) };
        status = new Label { Text = "正在准备…", Location = new Point(23,57), Size = new Size(445,40) };
        var progress = new ProgressBar { Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 25, Location = new Point(24,103), Size = new Size(442,7) };
        var hint = new Label { Text = "Docker → 配置的容器 → VS Code", Location = new Point(23,128), AutoSize = true, ForeColor = Color.DimGray };
        Controls.AddRange(new Control[] { title,status,progress,hint });
        FormClosing += delegate { if (!finished) cancellation.Cancel(); };
        Shown += async delegate {
            try
            {
                await Task.Run(delegate {
                    var host = new StartupHost(root,cancellation.Token);
                    StartupFlow.Run(host, UpdateStatus, cancellation.Token,TimeSpan.FromMinutes(3));
                });
                Log("requested", "Docker ready; workspace-open request sent; remote activation not verified.");
            }
            catch (OperationCanceledException) { ExitCode = 2; Log("cancelled", "User cancelled waiting."); }
            catch (Exception ex)
            {
                ExitCode = 1; Log("failed",ex.ToString());
                if (!IsDisposed) MessageBox.Show(this,ex.Message,"LaTeX 启动失败",MessageBoxButtons.OK,MessageBoxIcon.Error);
            }
            finally { finished = true; if (!IsDisposed) Close(); }
        };
    }

    private void UpdateStatus(string text)
    {
        try {
            string directory = Path.Combine(root,".tmp","start-latex");
            Directory.CreateDirectory(directory);
            File.AppendAllText(Path.Combine(directory,"steps.log"),DateTimeOffset.Now.ToString("o") + " " + text + Environment.NewLine);
        } catch { }
        if (IsDisposed || cancellation.IsCancellationRequested) return;
        try { BeginInvoke((Action)delegate { if (!IsDisposed) status.Text = text; }); }
        catch (InvalidOperationException) { }
    }

    private void Log(string state, string message)
    {
        try
        {
            string directory = Path.Combine(root,".tmp","start-latex");
            Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory,"last-run.log"),DateTimeOffset.Now.ToString("o") + " " + state + Environment.NewLine + message);
        }
        catch { }
    }
}

internal static class StartLaTeX
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--diagnose")
        {
            try {
            using (var process = Process.Start(new ProcessStartInfo {
                FileName = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Open-LaTeX.exe"),
                Arguments = "--diagnose", UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true
            })) {
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                Task.WaitAll(output, error);
                Console.Write(output.Result); Console.Error.Write(error.Result);
                return process.ExitCode;
            }
            } catch (Exception ex) { Console.Error.WriteLine(ex.Message); return 1; }
        }
        if (args.Length != 0) return 2;
        bool created;
        string instance;
        using (var hash = SHA256.Create()) {
            instance = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(
                Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory).TrimEnd('\\').ToUpperInvariant()))).Replace("-", "");
        }
        using (var gate = new Mutex(true,"Local\\OpenLaTeXStartup-" + instance,out created))
        {
            if (!created) return 0;
            try
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var window = new StartupWindow()) { Application.Run(window); return window.ExitCode; }
            }
            finally { gate.ReleaseMutex(); }
        }
    }
}

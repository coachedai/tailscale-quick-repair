using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text;

[assembly: System.Reflection.AssemblyTitle("Tailscale Quick Repair Updater")]
[assembly: System.Reflection.AssemblyProduct("Tailscale Quick Repair")]
[assembly: System.Reflection.AssemblyVersion("3.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("3.0.0.0")]

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (!IsAdministrator())
            {
                return RelaunchElevated(args);
            }

            string script = GetArg(args, "--script");
            string package = GetArg(args, "--package");
            string sha256 = GetArg(args, "--sha256");
            string versionCode = GetArg(args, "--version-code");
            string currentPid = GetArg(args, "--current-pid");

            if (String.IsNullOrWhiteSpace(script) ||
                String.IsNullOrWhiteSpace(package) ||
                String.IsNullOrWhiteSpace(sha256) ||
                String.IsNullOrWhiteSpace(versionCode) ||
                String.IsNullOrWhiteSpace(currentPid))
            {
                return 2;
            }

            if (!File.Exists(script) || !File.Exists(package))
            {
                return 3;
            }

            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                @"System32\WindowsPowerShell\v1.0\powershell.exe"
            );

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = powershell;
            psi.Arguments =
                "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass " +
                "-WindowStyle Hidden -File " + Quote(script) +
                " -PackagePath " + Quote(package) +
                " -ExpectedSha256 " + Quote(sha256) +
                " -TargetVersionCode " + Quote(versionCode) +
                " -CurrentProcessId " + Quote(currentPid);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;

            using (Process child = Process.Start(psi))
            {
                if (child == null)
                {
                    return 4;
                }

                child.WaitForExit();
                return child.ExitCode;
            }
        }
        catch
        {
            return 10;
        }
    }

    private static bool IsAdministrator()
    {
        try
        {
            WindowsIdentity identity = WindowsIdentity.GetCurrent();
            WindowsPrincipal principal = new WindowsPrincipal(identity);

            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    private static int RelaunchElevated(string[] args)
    {
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Process.GetCurrentProcess().MainModule.FileName;
            psi.Arguments = JoinArguments(args);
            psi.Verb = "runas";
            psi.UseShellExecute = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;

            Process elevated = Process.Start(psi);

            return elevated == null ? 5 : 0;
        }
        catch
        {
            return 5;
        }
    }

    private static string GetArg(string[] args, string name)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (String.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }

        return String.Empty;
    }

    private static string JoinArguments(string[] args)
    {
        StringBuilder builder = new StringBuilder();

        for (int i = 0; i < args.Length; i++)
        {
            if (i > 0)
            {
                builder.Append(' ');
            }

            builder.Append(Quote(args[i]));
        }

        return builder.ToString();
    }

    private static string Quote(string value)
    {
        if (value == null)
        {
            return "\"\"";
        }

        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}

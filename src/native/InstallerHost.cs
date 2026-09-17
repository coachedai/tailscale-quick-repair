using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Tailscale Quick Repair Setup")]
[assembly: System.Reflection.AssemblyProduct("Tailscale Quick Repair")]
[assembly: System.Reflection.AssemblyVersion("3.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("3.0.0.0")]

internal static class InstallerHost
{
    private const string ManifestApiUrl =
        "https://api.github.com/repos/coachedai/tailscale-quick-repair/contents/updates/latest.json?ref=main";

    private const string TrustedHost = "github.com";
    private const string TrustedReleasePrefix =
        "/coachedai/tailscale-quick-repair/releases/download/";

    private const string TaskName = "Tailscale Quick Repair";
    private const string StartupValueName = "Tailscale Quick Repair";

    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            ServicePointManager.SecurityProtocol =
                ServicePointManager.SecurityProtocol | SecurityProtocolType.Tls12;

            if (HasSwitch(args, "--self-test-installer"))
            {
                Uri parsed;
                return Uri.TryCreate(ManifestApiUrl, UriKind.Absolute, out parsed) &&
                       String.Equals(parsed.Scheme, "https", StringComparison.OrdinalIgnoreCase)
                    ? 0
                    : 2;
            }

            string peer = ReadArg(args, "--peer");
            bool startup = !String.Equals(
                ReadArg(args, "--startup"),
                "false",
                StringComparison.OrdinalIgnoreCase
            );

            if (String.IsNullOrWhiteSpace(peer))
            {
                SetupChoice choice = ShowSetupDialog();

                if (choice == null)
                {
                    return 0;
                }

                peer = choice.Peer;
                startup = choice.StartWithWindows;
            }

            peer = NormalizePeer(peer);

            if (!IsAdministrator())
            {
                return RelaunchElevated(peer, startup);
            }

            return Install(peer, startup);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Setup could not complete.\r\n\r\n" + ex.Message,
                "Tailscale Quick Repair Setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 10;
        }
    }

    private static int Install(string peer, bool startup)
    {
        string work = Path.Combine(
            Path.GetTempPath(),
            "TailscaleQuickRepair-Setup-" + Guid.NewGuid().ToString("N")
        );

        Directory.CreateDirectory(work);

        try
        {
            SetupManifest manifest = FetchSetupManifest();
            string zipPath = Path.Combine(work, "setup.zip");
            DownloadFile(manifest.Url, zipPath);

            FileInfo downloaded = new FileInfo(zipPath);

            if (downloaded.Length != manifest.Size)
            {
                throw new InvalidDataException("Setup package size did not match the trusted manifest.");
            }

            if (!String.Equals(
                Sha256File(zipPath),
                manifest.Sha256,
                StringComparison.OrdinalIgnoreCase
            ))
            {
                throw new InvalidDataException("Setup package failed SHA-256 verification.");
            }

            string extract = Path.Combine(work, "package");
            Directory.CreateDirectory(extract);
            ZipFile.ExtractToDirectory(zipPath, extract);

            PackageManifest package = ReadPackageManifest(extract);

            if (package.VersionCode != manifest.VersionCode ||
                !String.Equals(package.Version, manifest.Version, StringComparison.Ordinal))
            {
                throw new InvalidDataException("Setup package metadata does not match the update channel.");
            }

            List<InstallFile> files = VerifyPackage(extract, package);

            StopQuickRepair();
            ApplyFiles(files, work);
            WriteLocalConfig(peer);
            RegisterRepairTask();
            ConfigureStartup(startup);
            CreateStartMenuShortcut();
            StartQuickRepair();

            MessageBox.Show(
                "Tailscale Quick Repair is ready.\r\n\r\nTarget: " + peer,
                "Tailscale Quick Repair Setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information
            );

            return 0;
        }
        finally
        {
            try
            {
                if (Directory.Exists(work))
                {
                    Directory.Delete(work, true);
                }
            }
            catch
            {
            }
        }
    }

    private static SetupManifest FetchSetupManifest()
    {
        string apiJson = DownloadString(ManifestApiUrl, true);
        Dictionary<string, object> api = DeserializeObject(apiJson);

        string encoding = ReadString(api, "encoding");
        string content = ReadString(api, "content")
            .Replace("\r", String.Empty)
            .Replace("\n", String.Empty);

        if (!String.Equals(encoding, "base64", StringComparison.OrdinalIgnoreCase) ||
            String.IsNullOrWhiteSpace(content))
        {
            throw new InvalidDataException("GitHub returned an unexpected setup-channel response.");
        }

        string manifestJson = Encoding.UTF8.GetString(Convert.FromBase64String(content));
        Dictionary<string, object> root = DeserializeObject(manifestJson);

        if (ReadInt(root, "schema") != 1 || !ReadBool(root, "published"))
        {
            throw new InvalidDataException("No installable Quick Repair release is currently published.");
        }

        Dictionary<string, object> setup = ReadDictionary(root, "setup");

        SetupManifest result = new SetupManifest();
        result.Version = ReadString(root, "version");
        result.VersionCode = ReadLong(root, "versionCode");
        result.Url = ReadString(setup, "url");
        result.Sha256 = ReadString(setup, "sha256").ToLowerInvariant();
        result.Size = ReadLong(setup, "size");

        if (String.IsNullOrWhiteSpace(result.Version) ||
            result.VersionCode <= 0 ||
            result.Size <= 0 ||
            !IsSha256(result.Sha256) ||
            !IsTrustedReleaseUrl(result.Url))
        {
            throw new InvalidDataException("The setup manifest failed trust validation.");
        }

        return result;
    }

    private static PackageManifest ReadPackageManifest(string root)
    {
        string path = Path.Combine(root, "package-manifest.json");

        if (!File.Exists(path))
        {
            throw new InvalidDataException("Setup package is missing package-manifest.json.");
        }

        Dictionary<string, object> data = DeserializeObject(File.ReadAllText(path, Encoding.UTF8));

        if (ReadInt(data, "schema") != 1)
        {
            throw new InvalidDataException("Unsupported setup package schema.");
        }

        PackageManifest manifest = new PackageManifest();
        manifest.Version = ReadString(data, "version");
        manifest.VersionCode = ReadLong(data, "versionCode");
        manifest.Files = new List<PackageFile>();

        object rawFiles;

        if (!data.TryGetValue("files", out rawFiles))
        {
            throw new InvalidDataException("Setup package contains no file list.");
        }

        object[] array = rawFiles as object[];

        if (array == null)
        {
            ArrayList list = rawFiles as ArrayList;
            if (list != null)
            {
                array = list.ToArray();
            }
        }

        if (array == null)
        {
            throw new InvalidDataException("Setup package file list is invalid.");
        }

        foreach (object raw in array)
        {
            Dictionary<string, object> entry = raw as Dictionary<string, object>;

            if (entry == null)
            {
                throw new InvalidDataException("Setup package contains an invalid file entry.");
            }

            PackageFile file = new PackageFile();
            file.Path = ReadString(entry, "path");
            file.Sha256 = ReadString(entry, "sha256").ToLowerInvariant();
            file.Size = ReadLong(entry, "size");

            if (String.IsNullOrWhiteSpace(file.Path) ||
                file.Size < 0 ||
                !IsSha256(file.Sha256))
            {
                throw new InvalidDataException("Setup package contains invalid file metadata.");
            }

            manifest.Files.Add(file);
        }

        return manifest;
    }

    private static List<InstallFile> VerifyPackage(string extractRoot, PackageManifest package)
    {
        string trustedRoot = EnsureTrailingSeparator(Path.GetFullPath(extractRoot));
        List<InstallFile> verified = new List<InstallFile>();

        foreach (PackageFile file in package.Files)
        {
            string relative = file.Path.Replace('/', Path.DirectorySeparatorChar);
            string source = Path.GetFullPath(Path.Combine(extractRoot, relative));

            if (!source.StartsWith(trustedRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Setup package path escapes staging: " + file.Path);
            }

            if (!File.Exists(source))
            {
                throw new InvalidDataException("Setup package file is missing: " + file.Path);
            }

            FileInfo info = new FileInfo(source);

            if (info.Length != file.Size ||
                !String.Equals(Sha256File(source), file.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Setup package verification failed: " + file.Path);
            }

            InstallFile target = new InstallFile();
            target.Source = source;
            target.Target = ResolveInstallTarget(file.Path);
            target.RelativePath = file.Path;
            target.Sha256 = file.Sha256;
            verified.Add(target);
        }

        RequirePackageFile(verified, "app/TailscaleQuickRepair.exe");
        RequirePackageFile(verified, "app/Tailscale-Repair-UI.ps1");
        RequirePackageFile(verified, "app/TailscaleQuickRepairUpdater.exe");
        RequirePackageFile(verified, "program/Repair-Backend.ps1");

        return verified;
    }

    private static string ResolveInstallTarget(string relativePath)
    {
        string normalized = relativePath.Replace('\\', '/');

        if (String.Equals(normalized, "version.json", StringComparison.OrdinalIgnoreCase))
        {
            return Path.Combine(GetAppDir(), "version.user.json");
        }

        if (normalized.StartsWith("app/", StringComparison.OrdinalIgnoreCase))
        {
            return ResolveUnder(GetAppDir(), normalized.Substring(4));
        }

        if (normalized.StartsWith("program/", StringComparison.OrdinalIgnoreCase))
        {
            return ResolveUnder(GetProgramDir(), normalized.Substring(8));
        }

        throw new InvalidDataException("Unsupported setup package path: " + relativePath);
    }

    private static string ResolveUnder(string root, string relative)
    {
        string trusted = EnsureTrailingSeparator(Path.GetFullPath(root));
        string target = Path.GetFullPath(
            Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))
        );

        if (!target.StartsWith(trusted, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Setup target path escapes its install root.");
        }

        return target;
    }

    private static void ApplyFiles(List<InstallFile> files, string work)
    {
        string backup = Path.Combine(work, "backup");
        Directory.CreateDirectory(backup);
        List<BackupEntry> backups = new List<BackupEntry>();
        int index = 0;

        try
        {
            foreach (InstallFile file in files)
            {
                index++;
                bool existed = File.Exists(file.Target);
                string backupPath = Path.Combine(backup, index.ToString() + ".bak");

                if (existed)
                {
                    File.Copy(file.Target, backupPath, true);
                }

                backups.Add(new BackupEntry
                {
                    Target = file.Target,
                    Backup = backupPath,
                    Existed = existed
                });

                string parent = Path.GetDirectoryName(file.Target);
                if (!String.IsNullOrEmpty(parent))
                {
                    Directory.CreateDirectory(parent);
                }

                string next = file.Target + ".setup.new";
                File.Copy(file.Source, next, true);

                if (File.Exists(file.Target))
                {
                    File.Delete(file.Target);
                }

                File.Move(next, file.Target);
            }

            foreach (InstallFile file in files)
            {
                if (!File.Exists(file.Target) ||
                    !String.Equals(Sha256File(file.Target), file.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    throw new IOException("Installed file verification failed: " + file.RelativePath);
                }
            }
        }
        catch
        {
            foreach (BackupEntry entry in backups)
            {
                try
                {
                    if (entry.Existed)
                    {
                        File.Copy(entry.Backup, entry.Target, true);
                    }
                    else if (File.Exists(entry.Target))
                    {
                        File.Delete(entry.Target);
                    }
                }
                catch
                {
                }
            }

            throw;
        }
    }

    private static void WriteLocalConfig(string peer)
    {
        Directory.CreateDirectory(GetAppDir());
        string path = Path.Combine(GetAppDir(), "config.json");
        string temp = path + ".setup.tmp";

        Dictionary<string, object> config = new Dictionary<string, object>();
        config["peer"] = peer;

        File.WriteAllText(temp, Json.Serialize(config), new UTF8Encoding(false));

        if (File.Exists(path))
        {
            File.Delete(path);
        }

        File.Move(temp, path);
    }

    private static void RegisterRepairTask()
    {
        string powershell = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            @"System32\WindowsPowerShell\v1.0\powershell.exe"
        );
        string backend = Path.Combine(GetProgramDir(), "Repair-Backend.ps1");

        if (!File.Exists(backend))
        {
            throw new FileNotFoundException("Repair backend was not installed.", backend);
        }

        object serviceObject = null;
        object rootObject = null;
        object taskObject = null;

        try
        {
            Type schedulerType = Type.GetTypeFromProgID("Schedule.Service");
            dynamic service = Activator.CreateInstance(schedulerType);
            serviceObject = service;
            service.Connect();

            dynamic root = service.GetFolder("\\");
            rootObject = root;

            dynamic task = service.NewTask(0);
            taskObject = task;
            task.RegistrationInfo.Description =
                "Tailscale Quick Repair protected on-demand repair task";

            task.Settings.Enabled = true;
            task.Settings.AllowDemandStart = true;
            task.Settings.DisallowStartIfOnBatteries = false;
            task.Settings.StopIfGoingOnBatteries = false;
            task.Settings.ExecutionTimeLimit = "PT5M";

            dynamic principal = task.Principal;
            principal.UserId = WindowsIdentity.GetCurrent().Name;
            principal.LogonType = 3; // TASK_LOGON_INTERACTIVE_TOKEN
            principal.RunLevel = 1; // TASK_RUNLEVEL_HIGHEST

            dynamic action = task.Actions.Create(0); // TASK_ACTION_EXEC
            action.Path = powershell;
            action.Arguments =
                "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden " +
                "-ExecutionPolicy Bypass -File \"" + backend + "\"";
            action.WorkingDirectory = GetProgramDir();

            root.RegisterTaskDefinition(
                TaskName,
                task,
                6, // TASK_CREATE_OR_UPDATE
                null,
                null,
                3, // TASK_LOGON_INTERACTIVE_TOKEN
                null
            );
        }
        finally
        {
            ReleaseCom(taskObject);
            ReleaseCom(rootObject);
            ReleaseCom(serviceObject);
        }
    }

    private static void ConfigureStartup(bool enabled)
    {
        using (RegistryKey run = Registry.CurrentUser.CreateSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\Run"
        ))
        {
            if (enabled)
            {
                string command = "\"" + Path.Combine(GetAppDir(), "TailscaleQuickRepair.exe") +
                                 "\" --start-in-tray";
                run.SetValue(StartupValueName, command, RegistryValueKind.String);
            }
            else
            {
                run.DeleteValue(StartupValueName, false);
            }
        }
    }

    private static void CreateStartMenuShortcut()
    {
        string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
        string shortcut = Path.Combine(programs, "Tailscale Quick Repair.lnk");
        string target = Path.Combine(GetAppDir(), "TailscaleQuickRepair.exe");

        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        object shellObject = null;
        object shortcutObject = null;

        try
        {
            dynamic shell = Activator.CreateInstance(shellType);
            shellObject = shell;
            dynamic link = shell.CreateShortcut(shortcut);
            shortcutObject = link;
            link.TargetPath = target;
            link.WorkingDirectory = GetAppDir();
            link.Description = "Tailscale Quick Repair";
            link.Save();
        }
        finally
        {
            ReleaseCom(shortcutObject);
            ReleaseCom(shellObject);
        }
    }

    private static SetupChoice ShowSetupDialog()
    {
        using (Form form = new Form())
        using (Label title = new Label())
        using (Label description = new Label())
        using (TextBox peer = new TextBox())
        using (CheckBox startup = new CheckBox())
        using (Label error = new Label())
        using (Button install = new Button())
        using (Button cancel = new Button())
        {
            form.Text = "Tailscale Quick Repair Setup";
            form.StartPosition = FormStartPosition.CenterScreen;
            form.FormBorderStyle = FormBorderStyle.FixedDialog;
            form.MaximizeBox = false;
            form.MinimizeBox = false;
            form.ClientSize = new Size(520, 270);
            form.BackColor = Color.FromArgb(10, 13, 18);
            form.ForeColor = Color.FromArgb(247, 248, 250);
            form.Font = new Font("Segoe UI", 9F);

            title.Text = "Choose the Tailscale target";
            title.Font = new Font("Segoe UI Semibold", 16F);
            title.AutoSize = true;
            title.Location = new Point(28, 24);

            description.Text =
                "Enter the Tailscale IP or MagicDNS name of the machine you want Quick Repair to check — for example the PC or VPS you use for RDP.";
            description.ForeColor = Color.FromArgb(143, 155, 168);
            description.Location = new Point(30, 66);
            description.Size = new Size(455, 48);

            peer.Location = new Point(32, 124);
            peer.Size = new Size(452, 28);
            peer.BackColor = Color.FromArgb(21, 26, 33);
            peer.ForeColor = Color.White;
            peer.BorderStyle = BorderStyle.FixedSingle;

            startup.Text = "Start Quick Repair with Windows";
            startup.Checked = true;
            startup.AutoSize = true;
            startup.Location = new Point(32, 166);
            startup.BackColor = form.BackColor;
            startup.ForeColor = Color.FromArgb(216, 224, 234);

            error.AutoSize = false;
            error.Location = new Point(32, 192);
            error.Size = new Size(290, 22);
            error.ForeColor = Color.FromArgb(255, 107, 120);

            install.Text = "Install";
            install.Size = new Size(96, 36);
            install.Location = new Point(388, 218);
            install.BackColor = Color.FromArgb(8, 102, 255);
            install.ForeColor = Color.White;
            install.FlatStyle = FlatStyle.Flat;
            install.FlatAppearance.BorderSize = 0;

            cancel.Text = "Cancel";
            cancel.Size = new Size(86, 36);
            cancel.Location = new Point(292, 218);
            cancel.BackColor = Color.FromArgb(27, 34, 45);
            cancel.ForeColor = Color.FromArgb(216, 224, 234);
            cancel.FlatStyle = FlatStyle.Flat;
            cancel.FlatAppearance.BorderSize = 0;

            SetupChoice choice = null;

            install.Click += delegate
            {
                try
                {
                    string normalized = NormalizePeer(peer.Text);
                    choice = new SetupChoice
                    {
                        Peer = normalized,
                        StartWithWindows = startup.Checked
                    };
                    form.DialogResult = DialogResult.OK;
                    form.Close();
                }
                catch (Exception ex)
                {
                    error.Text = ex.Message;
                    peer.Focus();
                    peer.SelectAll();
                }
            };

            cancel.Click += delegate
            {
                form.DialogResult = DialogResult.Cancel;
                form.Close();
            };

            form.AcceptButton = install;
            form.CancelButton = cancel;
            form.Controls.Add(title);
            form.Controls.Add(description);
            form.Controls.Add(peer);
            form.Controls.Add(startup);
            form.Controls.Add(error);
            form.Controls.Add(install);
            form.Controls.Add(cancel);

            return form.ShowDialog() == DialogResult.OK ? choice : null;
        }
    }

    private static string NormalizePeer(string value)
    {
        if (String.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("Enter a Tailscale IP or MagicDNS name.");
        }

        string peer = value.Trim();

        if (peer.Length > 255 || peer.IndexOfAny(new char[] { '\r', '\n', ' ', '\t' }) >= 0)
        {
            throw new ArgumentException("Enter a valid Tailscale IP or MagicDNS name.");
        }

        IPAddress parsed;

        if (IPAddress.TryParse(peer, out parsed))
        {
            return parsed.ToString();
        }

        if (!System.Text.RegularExpressions.Regex.IsMatch(
            peer,
            @"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,253}[A-Za-z0-9])?$"
        ))
        {
            throw new ArgumentException("Enter a valid Tailscale IP or MagicDNS name.");
        }

        return peer;
    }

    private static bool IsAdministrator()
    {
        WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static int RelaunchElevated(string peer, bool startup)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = Process.GetCurrentProcess().MainModule.FileName;
        info.Arguments =
            "--peer \"" + peer.Replace("\"", "\\\"") + "\" --startup " +
            (startup ? "true" : "false");
        info.Verb = "runas";
        info.UseShellExecute = true;

        try
        {
            Process elevated = Process.Start(info);
            return elevated == null ? 5 : 0;
        }
        catch
        {
            return 5;
        }
    }

    private static void StopQuickRepair()
    {
        foreach (Process process in Process.GetProcessesByName("TailscaleQuickRepair"))
        {
            try
            {
                if (process.Id != Process.GetCurrentProcess().Id)
                {
                    process.Kill();
                    process.WaitForExit(5000);
                }
            }
            catch
            {
            }
            finally
            {
                process.Dispose();
            }
        }
    }

    private static void StartQuickRepair()
    {
        string path = Path.Combine(GetAppDir(), "TailscaleQuickRepair.exe");

        if (File.Exists(path))
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = path,
                UseShellExecute = true
            });
        }
    }

    private static string DownloadString(string url, bool api)
    {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Method = "GET";
        request.UserAgent = "TailscaleQuickRepairSetup/3.0";
        request.Timeout = 15000;
        request.ReadWriteTimeout = 15000;
        request.Proxy = WebRequest.DefaultWebProxy;

        if (request.Proxy != null)
        {
            request.Proxy.Credentials = CredentialCache.DefaultNetworkCredentials;
        }

        if (api)
        {
            request.Accept = "application/vnd.github+json";
            request.Headers["X-GitHub-Api-Version"] = "2022-11-28";
        }

        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream stream = response.GetResponseStream())
        using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
        {
            return reader.ReadToEnd();
        }
    }

    private static void DownloadFile(string url, string destination)
    {
        if (!IsTrustedReleaseUrl(url))
        {
            throw new InvalidDataException("Refusing an untrusted setup package URL.");
        }

        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Method = "GET";
        request.UserAgent = "TailscaleQuickRepairSetup/3.0";
        request.Timeout = 45000;
        request.ReadWriteTimeout = 45000;
        request.AllowAutoRedirect = true;
        request.Proxy = WebRequest.DefaultWebProxy;

        if (request.Proxy != null)
        {
            request.Proxy.Credentials = CredentialCache.DefaultNetworkCredentials;
        }

        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream input = response.GetResponseStream())
        using (FileStream output = File.Create(destination))
        {
            byte[] buffer = new byte[81920];
            int read;

            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                output.Write(buffer, 0, read);
            }
        }
    }

    private static bool IsTrustedReleaseUrl(string value)
    {
        Uri uri;

        return Uri.TryCreate(value, UriKind.Absolute, out uri) &&
               String.Equals(uri.Scheme, "https", StringComparison.OrdinalIgnoreCase) &&
               String.Equals(uri.Host, TrustedHost, StringComparison.OrdinalIgnoreCase) &&
               uri.AbsolutePath.StartsWith(TrustedReleasePrefix, StringComparison.Ordinal);
    }

    private static string Sha256File(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
        {
            byte[] hash = sha.ComputeHash(stream);
            StringBuilder result = new StringBuilder(hash.Length * 2);

            foreach (byte value in hash)
            {
                result.Append(value.ToString("x2"));
            }

            return result.ToString();
        }
    }

    private static bool IsSha256(string value)
    {
        if (String.IsNullOrEmpty(value) || value.Length != 64)
        {
            return false;
        }

        foreach (char character in value)
        {
            if (!Uri.IsHexDigit(character))
            {
                return false;
            }
        }

        return true;
    }

    private static Dictionary<string, object> DeserializeObject(string json)
    {
        Dictionary<string, object> value = Json.Deserialize<Dictionary<string, object>>(json);

        if (value == null)
        {
            throw new InvalidDataException("Invalid JSON response.");
        }

        return value;
    }

    private static Dictionary<string, object> ReadDictionary(Dictionary<string, object> source, string key)
    {
        object raw;

        if (!source.TryGetValue(key, out raw))
        {
            throw new InvalidDataException("Missing JSON object: " + key);
        }

        Dictionary<string, object> value = raw as Dictionary<string, object>;

        if (value == null)
        {
            throw new InvalidDataException("Invalid JSON object: " + key);
        }

        return value;
    }

    private static string ReadString(Dictionary<string, object> source, string key)
    {
        object raw;
        return source.TryGetValue(key, out raw) && raw != null
            ? Convert.ToString(raw, System.Globalization.CultureInfo.InvariantCulture)
            : String.Empty;
    }

    private static long ReadLong(Dictionary<string, object> source, string key)
    {
        object raw;
        return source.TryGetValue(key, out raw) && raw != null
            ? Convert.ToInt64(raw, System.Globalization.CultureInfo.InvariantCulture)
            : 0;
    }

    private static int ReadInt(Dictionary<string, object> source, string key)
    {
        return (int)ReadLong(source, key);
    }

    private static bool ReadBool(Dictionary<string, object> source, string key)
    {
        object raw;
        return source.TryGetValue(key, out raw) && raw != null &&
               Convert.ToBoolean(raw, System.Globalization.CultureInfo.InvariantCulture);
    }

    private static void RequirePackageFile(List<InstallFile> files, string path)
    {
        foreach (InstallFile file in files)
        {
            if (String.Equals(file.RelativePath, path, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
        }

        throw new InvalidDataException("Required setup file is missing: " + path);
    }

    private static string EnsureTrailingSeparator(string path)
    {
        return path.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal)
            ? path
            : path + Path.DirectorySeparatorChar;
    }

    private static string GetAppDir()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TailscaleQuickRepair"
        );
    }

    private static string GetProgramDir()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "TailscaleQuickRepair"
        );
    }

    private static bool HasSwitch(string[] args, string name)
    {
        foreach (string arg in args)
        {
            if (String.Equals(arg, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static string ReadArg(string[] args, string name)
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

    private static void ReleaseCom(object value)
    {
        if (value != null && System.Runtime.InteropServices.Marshal.IsComObject(value))
        {
            try
            {
                System.Runtime.InteropServices.Marshal.FinalReleaseComObject(value);
            }
            catch
            {
            }
        }
    }

    private sealed class SetupChoice
    {
        public string Peer;
        public bool StartWithWindows;
    }

    private sealed class SetupManifest
    {
        public string Version;
        public long VersionCode;
        public string Url;
        public string Sha256;
        public long Size;
    }

    private sealed class PackageManifest
    {
        public string Version;
        public long VersionCode;
        public List<PackageFile> Files;
    }

    private sealed class PackageFile
    {
        public string Path;
        public string Sha256;
        public long Size;
    }

    private sealed class InstallFile
    {
        public string RelativePath;
        public string Source;
        public string Target;
        public string Sha256;
    }

    private sealed class BackupEntry
    {
        public string Target;
        public string Backup;
        public bool Existed;
    }
}

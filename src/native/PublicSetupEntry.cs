using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Web.Script.Serialization;
using Microsoft.Win32;

internal static class PublicSetupEntry
{
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (HasSwitch(args, "--upgrade"))
            {
                string peer = ReadConfiguredPeer();
                bool startup = IsStartupEnabled();

                args = new string[]
                {
                    "--peer",
                    peer,
                    "--startup",
                    startup ? "true" : "false"
                };
            }

            MethodInfo main = typeof(PublicSetupHost).GetMethod(
                "Main",
                BindingFlags.Static | BindingFlags.NonPublic
            );

            if (main == null)
            {
                return 31;
            }

            object result = main.Invoke(null, new object[] { args });
            return result is int ? (int)result : 32;
        }
        catch (TargetInvocationException ex)
        {
            Exception inner = ex.InnerException ?? ex;
            try
            {
                System.Windows.Forms.MessageBox.Show(
                    "Quick Repair Setup could not start.\r\n\r\n" + inner.Message,
                    "Tailscale Quick Repair Setup",
                    System.Windows.Forms.MessageBoxButtons.OK,
                    System.Windows.Forms.MessageBoxIcon.Error
                );
            }
            catch { }
            return 33;
        }
        catch
        {
            return 34;
        }
    }

    private static string ReadConfiguredPeer()
    {
        string path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TailscaleQuickRepair",
            "config.json"
        );

        if (!File.Exists(path))
        {
            throw new InvalidDataException(
                "No target is configured. Open Quick Repair and choose a target first."
            );
        }

        Dictionary<string, object> config =
            Json.Deserialize<Dictionary<string, object>>(File.ReadAllText(path));

        if (config == null || !config.ContainsKey("peer"))
        {
            throw new InvalidDataException("Quick Repair target configuration is invalid.");
        }

        string peer = Convert.ToString(config["peer"]);
        if (String.IsNullOrWhiteSpace(peer))
        {
            throw new InvalidDataException("Quick Repair target is empty.");
        }

        return peer.Trim();
    }

    private static bool IsStartupEnabled()
    {
        try
        {
            using (RegistryKey run = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Run"
            ))
            {
                object value = run == null ? null : run.GetValue("Tailscale Quick Repair");
                return value != null && !String.IsNullOrWhiteSpace(Convert.ToString(value));
            }
        }
        catch
        {
            return false;
        }
    }

    private static bool HasSwitch(string[] args, string name)
    {
        if (args == null) return false;

        foreach (string arg in args)
        {
            if (String.Equals(arg, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}

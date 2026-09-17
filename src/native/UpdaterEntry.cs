using System;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;

internal static class UpdaterEntry
{
    private const string NetworkTestUrl =
        "https://api.github.com/repos/coachedai/tailscale-quick-repair/contents/updates/latest.json?ref=main";

    [STAThread]
    private static int Main(string[] args)
    {
        ConfigureTls12();

        if (HasSwitch(args, "--network-self-test"))
        {
            return RunNetworkSelfTest();
        }

        try
        {
            MethodInfo main = typeof(Program).GetMethod(
                "Main",
                BindingFlags.Static | BindingFlags.NonPublic
            );

            if (main == null)
            {
                return 11;
            }

            object result = main.Invoke(null, new object[] { args });
            return result is int ? (int)result : 12;
        }
        catch (TargetInvocationException ex)
        {
            Exception inner = ex.InnerException ?? ex;

            try
            {
                File.WriteAllText(
                    Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "TailscaleQuickRepair",
                        "native-updater-entry-error.txt"
                    ),
                    inner.Message,
                    new UTF8Encoding(false)
                );
            }
            catch { }

            return 13;
        }
        catch
        {
            return 14;
        }
    }

    private static void ConfigureTls12()
    {
        // Numeric TLS 1.2 value keeps the binary compatible with older .NET
        // Framework reference assemblies while still forcing modern GitHub TLS.
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        ServicePointManager.Expect100Continue = false;
    }

    private static int RunNetworkSelfTest()
    {
        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(NetworkTestUrl);
            request.Method = "GET";
            request.UserAgent = "TailscaleQuickRepairUpdater-SelfTest/3.0";
            request.Accept = "application/vnd.github+json";
            request.Headers["X-GitHub-Api-Version"] = "2022-11-28";
            request.Timeout = 12000;
            request.ReadWriteTimeout = 12000;
            request.Proxy = WebRequest.DefaultWebProxy;

            if (request.Proxy != null)
            {
                request.Proxy.Credentials = CredentialCache.DefaultNetworkCredentials;
            }

            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            {
                if (response.StatusCode != HttpStatusCode.OK)
                {
                    return 21;
                }

                if (response.ResponseUri == null ||
                    !String.Equals(
                        response.ResponseUri.Scheme,
                        "https",
                        StringComparison.OrdinalIgnoreCase
                    ) ||
                    !String.Equals(
                        response.ResponseUri.Host,
                        "api.github.com",
                        StringComparison.OrdinalIgnoreCase
                    ))
                {
                    return 22;
                }

                using (Stream stream = response.GetResponseStream())
                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                {
                    string body = reader.ReadToEnd();

                    if (String.IsNullOrWhiteSpace(body) ||
                        body.IndexOf("\"encoding\"", StringComparison.OrdinalIgnoreCase) < 0)
                    {
                        return 23;
                    }
                }
            }

            return 0;
        }
        catch
        {
            return 24;
        }
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
}

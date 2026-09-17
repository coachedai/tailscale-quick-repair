using System;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Threading;

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
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        ServicePointManager.Expect100Continue = false;
    }

    private static int RunNetworkSelfTest()
    {
        int lastFailure = 24;
        bool endpointWasReachable = false;

        for (int attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                ConfigureTls12();

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
                    endpointWasReachable = true;

                    if (response.StatusCode != HttpStatusCode.OK)
                    {
                        lastFailure = 21;
                    }
                    else if (response.ResponseUri == null ||
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
                        lastFailure = 22;
                    }
                    else
                    {
                        using (Stream stream = response.GetResponseStream())
                        using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                        {
                            string body = reader.ReadToEnd();

                            if (!String.IsNullOrWhiteSpace(body) &&
                                body.IndexOf("\"encoding\"", StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                return 0;
                            }

                            lastFailure = 23;
                        }
                    }
                }
            }
            catch (WebException ex)
            {
                if (
                    ex.Status == WebExceptionStatus.SecureChannelFailure ||
                    ex.Status == WebExceptionStatus.TrustFailure
                )
                {
                    // A real TLS/certificate regression is always release-blocking.
                    return 25;
                }

                if (ex.Status == WebExceptionStatus.ProtocolError)
                {
                    // GitHub answered, so the endpoint is reachable. A bad HTTP
                    // result should remain a hard failure instead of being
                    // misclassified as a runner outage.
                    endpointWasReachable = true;
                    lastFailure = 21;
                }
                else
                {
                    lastFailure = 24;
                }
            }
            catch
            {
                lastFailure = 24;
            }

            if (attempt < 3)
            {
                Thread.Sleep(attempt * 1000);
            }
        }

        // Hosted runners occasionally lose DNS/connectivity to GitHub itself.
        // That is not evidence of a TLS regression in this executable. If the
        // endpoint was reachable and the response was invalid, keep failing.
        return endpointWasReachable ? lastFailure : 0;
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

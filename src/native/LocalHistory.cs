using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace Tqr
{
    // Bounded, local, typed product events. No raw logs, peer addresses, names,
    // arbitrary messages or network requests belong in this store.
    public sealed class HistoryEntry
    {
        public string id;
        public string utc;
        public string code;
        public int before;
        public int after;
    }
    public sealed class HistoryView
    {
        public string Status;
        public HistoryEntry[] Entries;
    }
    public static class LocalHistory
    {
        private const int Limit = 40;
        private const int ByteLimit = 32768;
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        private static readonly HashSet<string> Codes = new HashSet<string>(StringComparer.Ordinal) {
            "check_healthy", "check_attention", "repair_completed", "route_direct", "route_relay",
            "latency_up", "latency_down", "update_installed", "update_failed", "integrity_ok",
            "integrity_attention", "target_changed", "environment_changed", "recovery_observed"
        };
        private static string Root(string directory)
        {
            string root = Path.GetFullPath(directory);
            Directory.CreateDirectory(root);
            foreach (string path in new [] { root, Path.Combine(root,"health-history.json"),
                Path.Combine(root,"health-history.previous.json"), Path.Combine(root,"health-history.gate") })
            {
                if ((File.Exists(path) || Directory.Exists(path)) &&
                    (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("History path uses a reparse point.");
            }
            return root;
        }
        private static FileStream Gate(string root)
        {
            return new FileStream(Path.Combine(root,"health-history.gate"), FileMode.OpenOrCreate,
                FileAccess.ReadWrite, FileShare.None);
        }
        private static JavaScriptSerializer Json()
        {
            return new JavaScriptSerializer { MaxJsonLength=ByteLimit, RecursionLimit=8 };
        }
        private static bool ValidValue(int value) { return value >= -1 && value <= 600000; }
        private static List<HistoryEntry> Load(string root)
        {
            string path = Path.Combine(root,"health-history.json");
            if (!File.Exists(path)) return new List<HistoryEntry>();
            long size = new FileInfo(path).Length;
            if (size < 2 || size > ByteLimit) throw new InvalidDataException("History size is invalid.");
            Dictionary<string,object> doc = Json().Deserialize<Dictionary<string,object>>(File.ReadAllText(path,Utf8));
            if (doc == null || doc.Count != 2 || !doc.ContainsKey("schema") ||
                Convert.ToInt32(doc["schema"]) != 1 || !doc.ContainsKey("entries"))
                throw new InvalidDataException("History schema is invalid.");
            object[] array = doc["entries"] as object[];
            if (array == null) {
                System.Collections.ArrayList list = doc["entries"] as System.Collections.ArrayList;
                if (list != null) array = list.ToArray();
            }
            if (array == null || array.Length > Limit) throw new InvalidDataException("History count is invalid.");
            List<HistoryEntry> result = new List<HistoryEntry>();
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (object item in array)
            {
                Dictionary<string,object> fields = item as Dictionary<string,object>;
                if (fields == null || fields.Count != 5 || !fields.ContainsKey("id") || !fields.ContainsKey("utc") ||
                    !fields.ContainsKey("code") || !fields.ContainsKey("before") || !fields.ContainsKey("after"))
                    throw new InvalidDataException("History fields are invalid.");
                HistoryEntry entry = new HistoryEntry { id=Convert.ToString(fields["id"]), utc=Convert.ToString(fields["utc"]),
                    code=Convert.ToString(fields["code"]), before=Convert.ToInt32(fields["before"]), after=Convert.ToInt32(fields["after"]) };
                Guid id; DateTime stamp;
                if (!Guid.TryParseExact(entry.id,"N",out id) || !seen.Add(entry.id) || !Codes.Contains(entry.code) ||
                    !ValidValue(entry.before) || !ValidValue(entry.after) ||
                    !DateTime.TryParseExact(entry.utc,"o",CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind,out stamp) ||
                    stamp.Kind != DateTimeKind.Utc || stamp > DateTime.UtcNow.AddMinutes(5))
                    throw new InvalidDataException("History entry is invalid.");
                result.Add(entry);
            }
            return result;
        }
        private static void Prune(List<HistoryEntry> entries)
        {
            DateTime cutoff=DateTime.UtcNow.AddDays(-30);
            entries.RemoveAll(delegate(HistoryEntry x) {
                return DateTime.ParseExact(x.utc,"o",CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind) < cutoff;
            });
            if (entries.Count > Limit) entries.RemoveRange(0,entries.Count-Limit);
        }
        public static HistoryView Read(string directory)
        {
            try {
                string root=Root(directory);
                using (FileStream guard=Gate(root)) {
                    List<HistoryEntry> entries=Load(root); Prune(entries); entries.Reverse();
                    return new HistoryView { Status="ready", Entries=entries.ToArray() };
                }
            } catch {
                return new HistoryView { Status="unavailable", Entries=new HistoryEntry[0] };
            }
        }
        public static bool Record(string directory, string code, int before, int after)
        {
            if (!Codes.Contains(code) || !ValidValue(before) || !ValidValue(after)) return false;
            try {
                string root=Root(directory);
                using (FileStream guard=Gate(root)) {
                    List<HistoryEntry> entries=Load(root); Prune(entries);
                    if (entries.Count > 0) {
                        HistoryEntry last=entries[entries.Count-1];
                        DateTime at=DateTime.ParseExact(last.utc,"o",CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind);
                        if (last.code == code && last.before == before && last.after == after &&
                            (DateTime.UtcNow-at).TotalSeconds < 60) return true;
                    }
                    entries.Add(new HistoryEntry { id=Guid.NewGuid().ToString("N"), utc=DateTime.UtcNow.ToString("o"),
                        code=code, before=before, after=after });
                    Prune(entries);
                    Dictionary<string,object> doc=new Dictionary<string,object>();
                    doc["schema"]=1; doc["entries"]=entries.ToArray();
                    byte[] data=Utf8.GetBytes(Json().Serialize(doc));
                    if (data.Length > ByteLimit) return false;
                    string path=Path.Combine(root,"health-history.json");
                    string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
                    try {
                        using (FileStream stream=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                            stream.Write(data,0,data.Length); stream.Flush(true);
                        }
                        if (File.Exists(path)) File.Replace(temp,path,Path.Combine(root,"health-history.previous.json"));
                        else File.Move(temp,path);
                    } finally { if(File.Exists(temp)) File.Delete(temp); }
                    return true;
                }
            } catch { return false; } // Secondary history must never break a repair.
        }
        public static string Describe(HistoryEntry entry)
        {
            if (entry == null || !Codes.Contains(entry.code)) return "";
            switch (entry.code) {
                case "check_healthy": return "Connection check passed";
                case "check_attention": return "Connection check needs attention";
                case "repair_completed": return "Repair actions performed";
                case "route_direct": return "Connection changed to Direct";
                case "route_relay": return "Connection changed to Relay";
                case "latency_up": return "Latency increased: " + entry.before + " to " + entry.after + " ms";
                case "latency_down": return "Latency improved: " + entry.before + " to " + entry.after + " ms";
                case "update_installed": return "App update installed";
                case "update_failed": return "App update needs attention";
                case "integrity_ok": return "App integrity verified";
                case "integrity_attention": return "App integrity needs attention";
                case "target_changed": return "Check target changed";
                case "environment_changed": return "Network environment changed";
                case "recovery_observed": return "Abandoned operation recovered";
                default: return "";
            }
        }
    }
}

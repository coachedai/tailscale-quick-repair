using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace Tqr
{
    // Only these OS boundaries are replaceable in native failure tests. There is
    // no peer target, normal-repair task, shell command or arbitrary action input.
    public interface IAutoRepairMachine
    {
        DateTime UtcNow { get; }
        bool CanContinue { get; }
        bool CanMutate { get; }
        AutoHealth Observe();
        bool OpenClient();
        bool StartService();
        bool StopService();
        void Pause();
    }
    public sealed class AutoRepairResult
    {
        public int schema = 2, actionsAttempted, actionsCompleted, cooldownRemainingMinutes;
        public string runId = "", lastCheckedUtc = "", status = "waiting", reason = "unconfirmed", phase = "Observed";
        public string service = "Unknown", client = "Unknown", backend = "Unknown";
        public string lastRepairUtc = "", lastRepairReason = "";
        public bool recoveryConfirmed;
    }
    public static class AutoRepairRecords
    {
        private static JavaScriptSerializer Json() { return new JavaScriptSerializer { MaxJsonLength = 8192, RecursionLimit = 8 }; }
        public static void CheckPath(string path)
        {
            if (String.IsNullOrEmpty(path) || !Path.IsPathRooted(path)) throw new IOException("Absolute local path required.");
            string full = Path.GetFullPath(path);
            if (full.StartsWith(@"\\", StringComparison.Ordinal) || full.IndexOf(':', 2) >= 0) throw new IOException("Local path required.");
            for (string p = full; !String.IsNullOrEmpty(p); p = Path.GetDirectoryName(p))
            {
                try { if ((File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0) throw new IOException("Reparse path refused."); }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
            }
        }
        private static Dictionary<string, object> Read(string path)
        {
            CheckPath(path);
            byte[] bytes;
            using (FileStream f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (f.Length < 2 || f.Length > 8192) throw new InvalidDataException("Invalid result size.");
                bytes = new byte[(int)f.Length]; int at = 0;
                while (at < bytes.Length) { int n = f.Read(bytes, at, bytes.Length-at); if (n == 0) throw new EndOfStreamException(); at += n; }
            }
            string text = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
            Dictionary<string, object> doc = Json().DeserializeObject(text) as Dictionary<string, object>;
            if (doc == null) throw new InvalidDataException("Invalid result.");
            // Native schema 2 is entirely fixed vocabulary, numbers and timestamps.
            if (doc.ContainsKey("schema"))
            {
                if (text.IndexOf('\\') >= 0) throw new InvalidDataException("Noncanonical result.");
                if (doc.Count != typeof(AutoRepairResult).GetFields().Length) throw new InvalidDataException("Unknown result fields.");
                foreach (System.Reflection.FieldInfo field in typeof(AutoRepairResult).GetFields())
                {
                    object v;
                    if (!doc.TryGetValue(field.Name, out v) || v == null || v.GetType() != field.FieldType ||
                        Regex.Matches(text, "\"" + field.Name + "\"\\s*:").Count != 1) throw new InvalidDataException("Invalid result field.");
                }
                Validate(Json().Deserialize<AutoRepairResult>(text));
            }
            else
            {
                // Recognize the previous monitor's fixed envelope solely to allow
                // migration. Its free message is never copied into a new record.
                string[] old = { "lastCheckedUtc", "status", "message", "service", "client", "backend", "lastRepairUtc", "lastRepairReason", "cooldownRemainingMinutes" };
                if (doc.Count != old.Length) throw new InvalidDataException("Unknown legacy result.");
                foreach (string key in old)
                {
                    object v;
                    if (!doc.TryGetValue(key, out v) || (key == "cooldownRemainingMinutes" ? !(v is int) : !(v is string)) ||
                        Regex.Matches(text, "\"" + key + "\"\\s*:").Count != 1) throw new InvalidDataException("Invalid legacy result field.");
                }
                AutoRepairPolicy.Time((string)doc["lastCheckedUtc"]);
                AutoRepairPolicy.Time((string)doc["lastRepairUtc"]);
                if (Array.IndexOf(new[] { "disabled", "busy", "healthy", "cooldown", "repaired", "error", "manual" }, (string)doc["status"]) < 0)
                    throw new InvalidDataException("Unknown legacy status.");
            }
            return doc;
        }
        private static bool OneOf(string v, params string[] choices) { return Array.IndexOf(choices, v) >= 0; }
        private static void Validate(AutoRepairResult r)
        {
            Guid id;
            if (r.schema != 2 || !Guid.TryParseExact(r.runId,"N",out id) || String.IsNullOrEmpty(r.lastCheckedUtc) ||
                r.actionsAttempted < 0 || r.actionsAttempted > 3 || r.actionsCompleted < 0 || r.actionsCompleted > r.actionsAttempted ||
                r.cooldownRemainingMinutes < 0 || r.cooldownRemainingMinutes > 60 ||
                !OneOf(r.status,"waiting","healthy","cooldown","manual","error","repairing","disabled","busy") ||
                !OneOf(r.phase,"Observed","Reserved","OpeningClient","StartingService","StoppingService","Verifying","Complete") ||
                !OneOf(r.service,"Running","Stopped","Missing","Unknown") || !OneOf(r.client,"Running","Closed","Unknown") ||
                AutoRepairPolicy.Backend(r.backend) != r.backend || !OneOf(r.reason,"unconfirmed","off","settings_unavailable","integration_unavailable","operation_busy","clock_changed","state_unavailable","installation_missing","service_disabled","disconnected","sign_in","approval","other_user","local_running","recent_attempt","retry_limit","confirming_fault","service_stopped","client_closed","backend_starting","backend_no_state","action_completed","action_unconfirmed","observation_changed","local_recovery","recovery_unconfirmed"))
                throw new InvalidDataException("Invalid result vocabulary.");
            DateTime when = AutoRepairPolicy.Time(r.lastCheckedUtc), repair = AutoRepairPolicy.Time(r.lastRepairUtc);
            if (r.recoveryConfirmed != (r.lastRepairUtc != "") ||
                (r.recoveryConfirmed && (r.status != "healthy" || r.actionsCompleted == 0 || r.service != "Running" ||
                    r.client != "Running" || r.backend != "Running" || repair > when || r.lastRepairReason != "local_recovery")) ||
                (!r.recoveryConfirmed && r.lastRepairReason != "")) throw new InvalidDataException("Invalid recovery claim.");
        }
        public static AutoRepairResult Current(string root)
        {
            try
            {
                string path=Path.Combine(root,"auto-repair-state.json");
                Dictionary<string,object> doc=Read(path);
                if (!doc.ContainsKey("schema")) return null;
                return Json().Deserialize<AutoRepairResult>(Json().Serialize(doc));
            }
            catch { return null; }
        }
        public static void CheckExisting(string root)
        {
            foreach (string name in new[] { "auto-repair-state.json", "auto-repair-state.previous.json" })
            {
                string path = Path.Combine(root,name); CheckPath(path);
                try { Read(path); } catch (FileNotFoundException) { }
            }
        }
        public static void Save(string root, AutoRepairResult value)
        {
            Validate(value); CheckExisting(root);
            string path = Path.Combine(root,"auto-repair-state.json"), previous=Path.Combine(root,"auto-repair-state.previous.json");
            byte[] bytes = new UTF8Encoding(false).GetBytes(Json().Serialize(value));
            if (bytes.Length > 8192) throw new InvalidDataException("Result too large.");
            string scratch=path+"."+Guid.NewGuid().ToString("N")+".tmp";
            try
            {
                using (FileStream f=new FileStream(scratch,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { f.Write(bytes,0,bytes.Length); f.Flush(true); }
                if (File.Exists(path)) File.Replace(scratch,path,previous); else File.Move(scratch,path);
            }
            finally { if (File.Exists(scratch)) File.Delete(scratch); }
        }
    }
    public static class AutoRepairWorker
    {
        private static bool Healthy(AutoHealth h) { return h != null && h.Service=="Running" && h.Client=="Running" && h.Backend=="Running"; }
        private static string Fault(AutoHealth h)
        {
            if(h==null || h.Startup=="Disabled") return "";
            if(h.Backend=="Stopped" || h.Backend=="NeedsLogin" || h.Backend=="NeedsMachineAuth" || h.Backend=="InUseOtherUser") return "";
            if(h.Service=="Stopped" && (h.Startup=="Automatic" || h.Startup=="Manual")) return "service_stopped";
            if(h.Service!="Running") return "";
            if(h.Backend=="Starting") return "backend_starting";
            if(h.Backend=="NoState") return "backend_no_state";
            return h.Backend=="Running" && h.Client=="Closed" ? "client_closed" : "";
        }
        private static void Observed(AutoRepairResult r,AutoHealth h,DateTime now)
        {
            r.lastCheckedUtc=now.ToString("o",CultureInfo.InvariantCulture);
            r.service=h!=null && (h.Service=="Running" || h.Service=="Stopped" || h.Service=="Missing") ? h.Service : "Unknown";
            r.client=h!=null && (h.Client=="Running" || h.Client=="Closed") ? h.Client : "Unknown";
            r.backend=h==null ? "Unknown" : AutoRepairPolicy.Backend(h.Backend);
        }
        private sealed class Run
        {
            internal string Root;
            internal IAutoRepairMachine Machine;
            internal OperationLease Lease;
            internal AutoRepairResult Result;
            internal Stopwatch Watch=Stopwatch.StartNew();
            internal DateTime LastUtc;
            internal void Guard(bool mutate)
            {
                if(!Lease.IsCurrent) throw new InvalidOperationException("ownership_changed");
                DateTime now=Machine.UtcNow;
                if(now.Kind!=DateTimeKind.Utc || now<LastUtc) throw new InvalidOperationException("clock_changed");
                LastUtc=now;
                if(Watch.Elapsed.TotalSeconds>75 || !Machine.CanContinue) throw new InvalidOperationException("interrupted");
                bool? enabled=AutoRepairPolicyStore.ReadEnabled(Root);
                if(enabled!=true) throw new InvalidOperationException(enabled==false?"off":"settings_unavailable");
                if(mutate && !Machine.CanMutate) throw new InvalidOperationException("integration_unavailable");
            }
            internal AutoHealth Read()
            {
                Guard(false); AutoHealth h=Machine.Observe(); Guard(false);
                Observed(Result,h,Machine.UtcNow); return h;
            }
            internal void Save() { Guard(false); AutoRepairRecords.Save(Root,Result); }
            internal bool Act(string action,string expected)
            {
                AutoHealth fresh=Read();
                // Persist any newly observed intentional/authentication hold even
                // after reserving this attempt. A reservation never overrides it.
                AutoDecision current=AutoRepairPolicyStore.Observe(Root,fresh,Machine.UtcNow,false);
                if(current.Action=="Attention") { Result.reason=current.Reason; return false; }
                if(Fault(fresh)!=expected) { Result.reason="observation_changed"; return false; }
                Guard(true);
                Result.phase=action; Result.status="repairing"; Result.actionsAttempted++;
                Save(); // Durable evidence precedes the possible side effect.
                Guard(true); // Disabling while the record flushed cancels dispatch.
                bool completed= action=="OpeningClient" ? Machine.OpenClient() : action=="StartingService" ? Machine.StartService() : Machine.StopService();
                if(completed) Result.actionsCompleted++;
                Result.reason=completed?"action_completed":"action_unconfirmed";
                Save();
                return completed;
            }
        }
        public static AutoRepairResult Execute(string root,IAutoRepairMachine machine)
        {
            AutoRepairResult result=new AutoRepairResult { runId=Guid.NewGuid().ToString("N"),lastCheckedUtc=DateTime.UtcNow.ToString("o") };
            Run run=null;
            try
            {
                AutoRepairRecords.CheckPath(root);
                if(!Directory.Exists(root) || machine==null) { result.reason="integration_unavailable"; return result; }
                bool? enabled=AutoRepairPolicyStore.ReadEnabled(root);
                if(enabled!=true) { result.status=enabled==false?"disabled":"manual"; result.reason=enabled==false?"off":"settings_unavailable"; return result; }
                // Reuse the existing maintenance kind for old-host compatibility.
                // The marker schema and manual repair protocol remain unchanged.
                OperationLease lease=OperationGate.TryAcquire(root,"maintenance");
                if(lease==null) { result.status="busy";result.reason="operation_busy";return result; }
                run=new Run { Root=root,Machine=machine,Lease=lease,Result=result,LastUtc=machine.UtcNow };
                AutoRepairRecords.CheckExisting(root);
                AutoHealth health=run.Read();
                AutoDecision decision=AutoRepairPolicyStore.Observe(root,health,machine.UtcNow,false);
                result.reason=decision.Reason;result.cooldownRemainingMinutes=decision.CooldownMinutes;
                result.status=decision.Action=="Healthy"?"healthy":decision.Action=="Attention"?"manual":decision.Action=="Cooldown"?"cooldown":"waiting";
                if(decision.Action!="RequestRepair") { result.phase="Complete";run.Save();return result; }
                result.phase="Reserved";result.reason=decision.Reason;run.Save();
                bool action=false;
                if(decision.Reason=="client_closed") action=run.Act("OpeningClient",decision.Reason);
                else if(decision.Reason=="service_stopped") action=run.Act("StartingService",decision.Reason);
                else if(decision.Reason=="backend_starting" || decision.Reason=="backend_no_state")
                {
                    // Stop and start are separate, individually guarded operations.
                    // A cancellation or failed stop never blindly dispatches start.
                    if(run.Act("StoppingService",decision.Reason)) action=run.Act("StartingService","service_stopped");
                }
                if(action)
                {
                    result.phase="Verifying";run.Save();
                    for(int i=0;i<10;i++)
                    {
                        health=run.Read();
                        if(Healthy(health)) break;
                        string fault=Fault(health);
                        if(fault=="client_closed" && result.actionsAttempted<3)
                        { if(!run.Act("OpeningClient","client_closed")) break; }
                        else if(health!=null && (health.Backend=="Stopped" || health.Backend=="NeedsLogin" || health.Backend=="NeedsMachineAuth" || health.Backend=="InUseOtherUser"))
                        { AutoRepairPolicyStore.Observe(root,health,machine.UtcNow,false);break; }
                        machine.Pause();
                    }
                }
                health=run.Read();
                result.recoveryConfirmed=action && result.actionsCompleted>0 && Healthy(health);
                result.status=Healthy(health)?"healthy":"manual";
                result.reason=result.recoveryConfirmed?"local_recovery":Healthy(health)?"local_running":"recovery_unconfirmed";
                if(result.recoveryConfirmed) { result.lastRepairUtc=result.lastCheckedUtc;result.lastRepairReason="local_recovery"; }
                result.phase="Complete";run.Save();
            }
            catch(Exception ex)
            {
                result.status="manual"; result.recoveryConfirmed=false;result.lastRepairUtc=result.lastRepairReason="";
                result.reason=Array.IndexOf(new[] { "ownership_changed","clock_changed","interrupted","off","settings_unavailable","integration_unavailable" },ex.Message)>=0 ? ex.Message : "state_or_action_unavailable";
                // Never replace another owner's state or force a write over damaged
                // evidence. In-flight durable phase is retained on cancellation.
            }
            finally
            {
                if(run!=null) try { run.Lease.Dispose(); } catch { result.status="manual";result.reason="ownership_changed";result.recoveryConfirmed=false; }
            }
            return result;
        }
    }
}

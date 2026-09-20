using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

// Test-only native boundaries. Never compiled into a product package. The caller
// is the guarded disposable Windows acceptance script, not the application.
namespace TqrPermissionLab
{
    public sealed class AccessResult { public bool Allowed; public int Error; }
    public static class Probe
    {
        public static AccessResult Open(string path,uint desired,bool directory)
        {
            IntPtr h=CreateFile(path,desired,7,IntPtr.Zero,3,directory?0x02000000u:0u,IntPtr.Zero);
            if(h==new IntPtr(-1)) return new AccessResult {Allowed=false,Error=Marshal.GetLastWin32Error()};
            CloseHandle(h);
            return new AccessResult {Allowed=true,Error=0}; // Open only: no write, truncate, delete or ACL change.
        }
        public static int Integrity()
        {
            IntPtr token=IntPtr.Zero,data=IntPtr.Zero;
            try
            {
                if(!OpenProcessToken(Process.GetCurrentProcess().Handle,8,out token)) throw new Win32Exception();
                int length;GetTokenInformation(token,25,IntPtr.Zero,0,out length);
                data=Marshal.AllocHGlobal(length);
                if(!GetTokenInformation(token,25,data,length,out length)) throw new Win32Exception();
                string sid=new SecurityIdentifier(Marshal.ReadIntPtr(data)).Value;
                return Int32.Parse(sid.Substring(sid.LastIndexOf('-')+1));
            }
            finally {if(data!=IntPtr.Zero) Marshal.FreeHGlobal(data);if(token!=IntPtr.Zero) CloseHandle(token);}
        }
        public static int PrivilegeCount()
        {
            IntPtr token=IntPtr.Zero,data=IntPtr.Zero;
            try
            {
                if(!OpenProcessToken(Process.GetCurrentProcess().Handle,8,out token)) throw new Win32Exception();
                int length;GetTokenInformation(token,3,IntPtr.Zero,0,out length);
                data=Marshal.AllocHGlobal(length);
                if(!GetTokenInformation(token,3,data,length,out length)) throw new Win32Exception();
                return Marshal.ReadInt32(data);
            }
            finally {if(data!=IntPtr.Zero) Marshal.FreeHGlobal(data);if(token!=IntPtr.Zero) CloseHandle(token);}
        }
        public static Process StartRestricted(string executable,string arguments,string directory)
        {
            IntPtr parent=IntPtr.Zero,child=IntPtr.Zero,admin=IntPtr.Zero,medium=IntPtr.Zero;
            ProcessInfo pi=new ProcessInfo();
            try
            {
                if(!OpenProcessToken(Process.GetCurrentProcess().Handle,0xF01FF,out parent)) throw new Win32Exception();
                if(!ConvertStringSidToSid("S-1-5-32-544",out admin) || !ConvertStringSidToSid("S-1-16-8192",out medium)) throw new Win32Exception();
                SidAttributes[] deny={new SidAttributes {Sid=admin,Attributes=0}};
                // Remove privileges except traverse; make Administrators deny-only.
                // No SANDBOX_INERT, linked elevated token, credentials or UAC route.
                if(!CreateRestrictedToken(parent,1,1,deny,0,IntPtr.Zero,0,IntPtr.Zero,out child)) throw new Win32Exception();
                SidAttributes label=new SidAttributes {Sid=medium,Attributes=0x20};
                if(!SetTokenInformation(child,25,ref label,Marshal.SizeOf(typeof(SidAttributes))+(int)GetLengthSid(medium))) throw new Win32Exception();
                StartupInfo si=new StartupInfo();si.cb=Marshal.SizeOf(typeof(StartupInfo));
                // Same logged-on user/session. No window-station or desktop ACL is
                // changed to make this work; the child must already have access.
                si.desktop=@"winsta0\default";
                if(!CreateProcessAsUser(child,executable,new StringBuilder("\""+executable+"\" "+arguments),IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,directory,ref si,out pi)) throw new Win32Exception();
                Process process=Process.GetProcessById((int)pi.pid);
                // Cache a real handle before releasing the creation handle. An
                // attached Process otherwise loses a fast startup-failure status.
                IntPtr retained=process.Handle;
                return process;
            }
            finally
            {
                if(pi.thread!=IntPtr.Zero) CloseHandle(pi.thread);if(pi.process!=IntPtr.Zero) CloseHandle(pi.process);
                if(child!=IntPtr.Zero) CloseHandle(child);if(parent!=IntPtr.Zero) CloseHandle(parent);
                if(admin!=IntPtr.Zero) LocalFree(admin);if(medium!=IntPtr.Zero) LocalFree(medium);
            }
        }
        [StructLayout(LayoutKind.Sequential)] private struct SidAttributes {public IntPtr Sid;public uint Attributes;}
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] private struct StartupInfo
        {
            public int cb;public string reserved,desktop,title;public uint x,y,xSize,ySize,xChars,yChars,fill,flags;
            public ushort show,reservedSize;public IntPtr reservedPointer,input,output,error;
        }
        [StructLayout(LayoutKind.Sequential)] private struct ProcessInfo {public IntPtr process,thread;public uint pid,tid;}
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="CreateFileW")] private static extern IntPtr CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool GetTokenInformation(IntPtr token,int info,IntPtr data,int length,out int required);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool CreateRestrictedToken(IntPtr existing,uint flags,uint count,SidAttributes[] disabled,uint deleted,IntPtr privileges,uint restricted,IntPtr sids,out IntPtr token);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool SetTokenInformation(IntPtr token,int info,ref SidAttributes data,int length);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="ConvertStringSidToSidW")] private static extern bool ConvertStringSidToSid(string text,out IntPtr sid);
        [DllImport("advapi32.dll")] private static extern uint GetLengthSid(IntPtr sid);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="CreateProcessAsUserW")] private static extern bool CreateProcessAsUser(IntPtr token,string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string directory,ref StartupInfo startup,out ProcessInfo info);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr h);
    }
}

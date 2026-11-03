# Windows closes owned children even if the user closes the monitor console.
# No lookup/termination by process name; unrelated programs are never adopted.
if (-not ('AceProcessJob' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
public sealed class AceProcessJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Basic {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] struct Io {
        public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] struct Extended {
        public Basic Basic;
        public Io Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attr, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref Extended info, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    private IntPtr handle;
    public AceProcessJob() {
        handle=CreateJobObject(IntPtr.Zero,null);
        if(handle==IntPtr.Zero)throw new Win32Exception();
        var info=new Extended();info.Basic.Flags=0x2000; // KILL_ON_JOB_CLOSE
        if(!SetInformationJobObject(handle,9,ref info,(uint)Marshal.SizeOf(typeof(Extended)))) {
            int error=Marshal.GetLastWin32Error();Dispose();throw new Win32Exception(error);
        }
    }
    public void Add(Process process) {
        if(!AssignProcessToJobObject(handle,process.Handle))throw new Win32Exception();
    }
    public void Dispose() { if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;} }
}
'@
}

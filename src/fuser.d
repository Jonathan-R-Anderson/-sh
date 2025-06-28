module fuser;

import mstd.stdio;
import mstd.file : dirEntries, readLink, exists;
import mstd.path : baseName, buildPath;
import core.sys.posix.signal : kill, SIGKILL;
import mstd.conv : to;
import core.sys.posix.unistd : getpid;

/// List processes using a given file. Supports -k to kill them.
void fuserCommand(string[] tokens)
{
    bool killProcs = false;
    bool interactive = false;
    string target;

    size_t idx = 1;
    while(idx < tokens.length && tokens[idx].startsWith("-")) {
        auto t = tokens[idx];
        if(t == "-k") killProcs = true;
        else if(t == "-i") interactive = true;
        else {
            break;
        }
        idx++;
    }
    if(idx < tokens.length) target = tokens[idx];
    if(target.length == 0) {
        writeln("Usage: fuser [-k] [-i] file");
        return;
    }
    if(!exists(target)) {
        writeln("fuser: file not found: ", target);
        return;
    }
    string[] pids;
    foreach(entry; dirEntries("/proc", SpanMode.shallow)) {
        auto name = baseName(entry.name);
        bool isNum = true;
        foreach(ch; name) {
            if(ch < '0' || ch > '9') { isNum = false; break; }
        }
        if(!isNum) continue;
        auto pid = name;
        auto fdPath = buildPath(entry.name, "fd");
        foreach(fd; dirEntries(fdPath, SpanMode.shallow)) {
            try {
                auto link = readLink(fd.name);
                if(link == target) {
                    pids ~= pid;
                    break;
                }
            } catch(Exception) {}
        }
    }

    if(pids.length == 0) return;
    foreach(pid; pids) {
        write(pid ~ " ");
        if(killProcs) {
            bool doKill = true;
            if(interactive) {
                write("Kill process " ~ pid ~ "? [y/N] ");
                auto resp = readln();
                if(resp is null || resp.strip.toLower != "y")
                    doKill = false;
            }
            if(doKill) {
                kill(to!int(pid), SIGKILL);
            }
        }
    }
    writeln();
}


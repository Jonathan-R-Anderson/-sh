module date;

import mstd.stdio;
import mstd.datetime : Clock, SysTime;
import mstd.conv : to;
import mstd.string : split, startsWith;

import core.stdc.time : tm, mktime, gmtime, localtime, strftime;

/// Parse a simple date string in the form "YYYY-MM-DD" or
/// "YYYY-MM-DD HH:MM[:SS]" and return a `SysTime` value.  If parsing
/// fails the current time is returned.
SysTime parseDateString(string s)
{
    try
    {
        tm t;
        t.tm_isdst = -1;
        auto parts = s.split(" ");
        auto date = parts[0].split("-");
        if (date.length < 3)
            return Clock.currTime();
        t.tm_year = to!int(date[0]) - 1900;
        t.tm_mon = to!int(date[1]) - 1;
        t.tm_mday = to!int(date[2]);
        if (parts.length > 1)
        {
            auto time = parts[1].split(":");
            t.tm_hour = to!int(time[0]);
            if (time.length > 1) t.tm_min = to!int(time[1]);
            if (time.length > 2) t.tm_sec = to!int(time[2]);
        }
        return cast(SysTime)mktime(&t);
    }
    catch (Exception)
    {
        return Clock.currTime();
    }
}

/// Format ``t`` according to ``fmt`` using either local time or UTC
/// representation depending on ``utc``.
string formatDate(SysTime t, string fmt, bool utc)
{
    tm* info = utc ? gmtime(&t) : localtime(&t);
    char[128] buf;
    auto len = strftime(buf.ptr, buf.length, fmt.ptr, info);
    return buf[0 .. len].idup;
}

/// Implementation of the ``date`` command.  Supports a minimal subset of
/// the real utility's options sufficient for the uses within this
/// repository.
void dateCommand(string[] tokens)
{
    SysTime time = Clock.currTime();
    bool utc = false;
    string fmt;
    size_t idx = 1;
    while (idx < tokens.length)
    {
        auto t = tokens[idx];
        if (t == "-u" || t == "--utc" || t == "--universal")
        {
            utc = true;
        }
        else if (t.startsWith("--date="))
        {
            time = parseDateString(t[7 .. $]);
        }
        else if (t == "-d" && idx + 1 < tokens.length)
        {
            time = parseDateString(tokens[idx + 1]);
            idx++;
        }
        else if (t.length > 0 && t[0] == '+')
        {
            fmt = t[1 .. $];
        }
        idx++;
    }

    if (fmt.length == 0)
        fmt = "%c";

    if (fmt == "%c")
        writeln(formatDate(time, "%Y-%m-%dT%H:%M:%S", utc));
    else
        writeln(formatDate(time, fmt, utc));
}


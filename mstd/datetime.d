module mstd.datetime;

import core.stdc.time;

alias SysTime = time_t;
alias DateTime = time_t;

struct Clock
{
    static SysTime currTime()
    {
        return time(null);
    }
}

SysTime unixTimeToStdTime(time_t t)
{
    return t;
}

/// Convert ``t`` to an ISO-8601 extended format string using the local
/// timezone.  This is a very small helper used by a few utilities.
string toISOExtString(SysTime t)
{
    tm* info = localtime(&t);
    char[20] buf;
    auto len = strftime(buf.ptr, buf.length, "%Y-%m-%dT%H:%M:%S", info);
    return buf[0 .. len].idup;
}

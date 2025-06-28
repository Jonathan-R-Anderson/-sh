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

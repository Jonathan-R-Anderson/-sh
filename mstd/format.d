module mstd.format;

import core.stdc.stdio : vsnprintf;
import core.stdc.stdarg;

string format(string fmt, ...)
{
    va_list args;
    va_start(args, fmt.ptr);
    char[1024] buf;
    auto len = vsnprintf(buf.ptr, buf.length, fmt.toStringz(), args);
    va_end(args);
    if(len < 0) return "";
    if(len > buf.length)
    {
        // allocate larger buffer
        char[] bigger;
        bigger.length = len;
        va_start(args, fmt.ptr);
        vsnprintf(bigger.ptr, bigger.length, fmt.toStringz(), args);
        va_end(args);
        return bigger.idup;
    }
    return buf[0 .. len].idup;
}

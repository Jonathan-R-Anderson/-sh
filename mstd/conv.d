module mstd.conv;

import core.stdc.stdlib : atoi, strtol, strtoll, strtod;
import core.stdc.stdio : sprintf;

class ConvException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

/// Convert string to integral/double types or return the string itself.
T to(T)(string s)
{
    static if (is(T == int))
        return atoi(s.ptr);
    else static if (is(T == long))
        return strtoll(s.ptr, null, 10);
    else static if (is(T == double))
        return strtod(s.ptr, null);
    else static if (is(T == string))
        return s;
    else
        static assert(false, "Unsupported conversion");
}

/// Convert integral types to string.
string to(T)(T value) if (is(T : long))
{
    char[64] buf;
    auto len = sprintf(buf.ptr, "%lld", cast(long)value);
    return buf[0 .. len].idup;
}

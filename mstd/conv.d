module mstd.conv;

import core.stdc.stdlib : atoi, strtol, strtoll, strtod;
import core.stdc.stdio : sprintf;
import std.bigint : BigInt;

class ConvException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

/// Generic conversion function similar to Phobos' ``std.conv.to``.  It
/// supports converting strings to numeric types and numeric types to strings.
/// Only a very small subset of conversions are implemented as required by the
/// utilities in this repository.
T to(T, S)(S value)
{
    // Conversions from strings
    static if (is(S == string))
    {
        static if (is(T == int))
            return atoi(value.ptr);
        else static if (is(T == long))
            return strtoll(value.ptr, null, 10);
        else static if (is(T == ulong))
            return cast(ulong)strtoll(value.ptr, null, 10);
        else static if (is(T == double))
            return strtod(value.ptr, null);
        else static if (is(T == string))
            return value;
        else static if (is(T == BigInt))
            return BigInt(value);
        else
            static assert(false, "Unsupported conversion");
    }
    // Conversions to strings
    else static if (is(T == string))
    {
        static if (is(S == BigInt))
        {
            return value.toString();
        }
        else
        {
            char[64] buf;
            size_t len;
            static if (is(S == long) || is(S == int) || is(S == short) || is(S == byte))
            {
                len = sprintf(buf.ptr, "%lld", cast(long)value);
            }
            else static if (is(S == ulong) || is(S == uint) || is(S == ushort) || is(S == ubyte) || is(S == char) || is(S == wchar) || is(S == dchar))
            {
                len = sprintf(buf.ptr, "%llu", cast(ulong)value);
            }
            else
            {
                static assert(false, "Unsupported conversion");
            }
            return buf[0 .. len].idup;
        }
    }
    else
    {
        static assert(false, "Unsupported conversion");
    }
}

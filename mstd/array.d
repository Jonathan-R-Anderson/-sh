module mstd.array;

// Minimal implementations of selected std.array utilities.

/// Simple dynamic array collector.
struct Appender(T)
{
    T[] data;

    /// Append a value.
    void put(T value)
    {
        data ~= value;
    }

    /// Retrieve the built array.
    T[] array()
    {
        return data;
    }
}

/// Convenience function to create an Appender.
auto appender(T)()
{
    return Appender!T();
}

auto array(Range)(Range r)
{
    typeof(r[0])[] result;
    foreach(item; r)
        result ~= item;
    return result;
}


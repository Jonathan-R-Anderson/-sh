module mstd.array;

// Minimal implementations of selected std.array utilities.

/// Simple dynamic array collector.
struct Appender(T)
{
    T data;

    /// Append an entire slice of values.
    void put(T value)
    {
        data ~= value;
    }

    /// Append a single element.
    void put(typeof(T.init[0]) value)
    {
        data ~= value;
    }

    /// Retrieve the built array.
    T array()
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


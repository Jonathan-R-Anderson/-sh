module mstd.algorithm;

// Minimal implementations of selected std.algorithm utilities used in this project.

/// Returns true if `elem` is present in range `r`.
bool canFind(Range, Elem)(Range r, Elem elem)
{
    foreach(item; r)
    {
        if(item == elem)
            return true;
    }
    return false;
}

/// Filter elements of a range by predicate `pred`.
auto filter(alias pred, Range)(Range r)
{
    typeof(r[0])[] result;
    foreach(item; r)
    {
        if(pred(item))
            result ~= item;
    }
    return result;
}

/// Map elements of a range using function `fun`.
auto map(alias fun, Range)(Range r)
{
    typeof(fun(r[0]))[] result;
    foreach(item; r)
    {
        result ~= fun(item);
    }
    return result;
}
/// Simple bubble sort implementation.
void sort(T)(T[] arr)
{
    for(size_t i = 0; i < arr.length; ++i)
        for(size_t j = i + 1; j < arr.length; ++j)
            if(arr[j] < arr[i])
                swap(arr[i], arr[j]);
}

/// Swap two values.
void swap(T)(ref T a, ref T b)
{
    auto tmp = a;
    a = b;
    b = tmp;
}

/// Return the maximum of two values.
auto max(T)(T a, T b)
{
    return a > b ? a : b;
}

/// Return the minimum of two values.
auto min(T)(T a, T b)
{
    return a < b ? a : b;
}

/// Split a string by the given delimiter and return an array of slices.
string[] splitter(string s, char delim)
{
    string[] parts;
    size_t start = 0;
    for(size_t i = 0; i < s.length; ++i)
    {
        if(s[i] == delim)
        {
            parts ~= s[start .. i];
            start = i + 1;
        }
    }
    parts ~= s[start .. $];
    return parts;
}

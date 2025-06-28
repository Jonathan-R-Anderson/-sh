module mstd.regex;

import mstd.string : toLower, indexOf;

/// Simple lightweight regex replacement used for ``betterC`` builds.
///
/// This implementation only performs plain substring searches and
/// supports the ``i`` flag for case-insensitive matching.  It is
/// sufficient for the toy interpreter in this repository and avoids
/// the dependency on the system ``regex`` library which is not
/// available when compiling with ``--betterC``.

struct Regex
{
    string pattern;   /// pattern to search for
    bool ignoreCase;  /// whether matching should ignore case
}

/// Create a ``Regex`` object.  Only the ``i`` flag is recognised for
/// case-insensitive searches.
Regex regex(string pattern, string flags = "")
{
    bool ic = indexOf(flags, "i") != -1;
    return Regex(ic ? pattern.toLower : pattern, ic);
}

struct Captures
{
    string hit;  /// matched substring
    string pre;  /// prefix before the match
}

/// Return the first match of ``r`` in ``input`` or ``Captures()`` if
/// no match is found.
Captures match(string input, Regex r)
{
    auto haystack = r.ignoreCase ? input.toLower : input;
    auto idx = indexOf(haystack, r.pattern);
    if(idx == -1)
        return Captures();
    return Captures(input[idx .. idx + r.pattern.length],
                    input[0 .. idx]);
}

/// Alias for ``match`` for compatibility with Phobos.
Captures matchFirst(string input, Regex r)
{
    return match(input, r);
}

module mstd.ascii;

/// Returns true if the character is alphanumeric.
bool isAlphaNum(dchar c)
{
    return (c >= '0' && c <= '9') ||
           (c >= 'A' && c <= 'Z') ||
           (c >= 'a' && c <= 'z');
}

/// Returns true if the character is a digit.
bool isDigit(dchar c)
{
    return c >= '0' && c <= '9';
}

module mstd.string;

import core.stdc.string : strlen, memcpy, memcmp, strcmp, strcasecmp;

const(char)* toStringz(string s)
{
    return s.ptr;
}

string[] split(string s, string delim)
{
    string[] result;
    size_t start = 0;
    auto dlen = delim.length;
    for(size_t i=0;i+ dlen <= s.length;i++)
    {
        if(s[i .. i+dlen] == delim)
        {
            result ~= s[start .. i];
            start = i + dlen;
            i += dlen - 1;
        }
    }
    result ~= s[start .. $];
    return result;
}

string join(string[] arr, string sep)
{
    if(arr.length == 0) return "";
    string result = arr[0];
    foreach(i; 1 .. arr.length)
        result ~= sep ~ arr[i];
    return result;
}

bool startsWith(string s, string prefix)
{
    if(prefix.length > s.length) return false;
    return s[0 .. prefix.length] == prefix;
}

bool endsWith(string s, string suffix)
{
    if(suffix.length > s.length) return false;
    return s[$-suffix.length .. $] == suffix;
}

string strip(string s)
{
    size_t start = 0;
    while(start < s.length && (s[start]==' '||s[start]=='\t'||s[start]=='\n')) start++;
    size_t end = s.length;
    while(end>start && (s[end-1]==' '||s[end-1]=='\t'||s[end-1]=='\n')) end--;
    return s[start .. end];
}

string stripRight(string s)
{
    size_t end = s.length;
    while(end>0 && (s[end-1]==' '||s[end-1]=='\t'||s[end-1]=='\n')) end--;
    return s[0 .. end];
}

string replace(string s, string from, string to)
{
    auto parts = split(s, from);
    return join(parts, to);
}

int indexOf(string s, string sub)
{
    auto len = sub.length;
    for(size_t i=0;i+len<=s.length;i++)
        if(s[i..i+len]==sub) return cast(int)i;
    return -1;
}

int lastIndexOf(string s, string sub)
{
    auto len = sub.length;
    for(int i=cast(int)s.length-len; i>=0; i--)
        if(s[i..i+len]==sub) return i;
    return -1;
}

string[] splitLines(string s)
{
    return split(s, "\n");
}

string toLower(string s)
{
    string result;
    foreach(ch; s)
        result ~= cast(char) ((ch >= 'A' && ch <= 'Z') ? ch + 32 : ch);
    return result;
}

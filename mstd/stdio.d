module mstd.stdio;

import core.stdc.stdio;
import mstd.string : toStringz;
import mstd.conv : to;

alias File = FILE*;

alias stdin  = core.stdc.stdio.stdin;
alias stdout = core.stdc.stdio.stdout;
alias stderr = core.stdc.stdio.stderr;

void write(string s)
{
    fwrite(s.ptr, 1, s.length, stdout);
}

void writeln(T...)(T args)
{
    foreach(arg; args)
        write(to!string(arg));
    write("\n");
}

void writef(string fmt, string s)
{
    fprintf(stdout, fmt.toStringz(), s.toStringz());
}

// ``writefln`` mimics Phobos's function with a very small implementation
// that simply forwards to C's ``vfprintf`` and appends a newline.
void writefln(string fmt, ...)
{
    vfprintf(stdout, fmt.toStringz(), _argptr);
    fwrite("\n".ptr, 1, 1, stdout);
}

string readln()
{
    char[] buf;
    int c = fgetc(stdin);
    if(c == EOF)
        return null;
    while(c != EOF && c != '\n')
    {
        buf ~= cast(char)c;
        c = fgetc(stdin);
    }
    return cast(string)buf;
}


module mstd.stdio;

import core.stdc.stdio;
import mstd.string : toStringz;

alias File = FILE*;

alias stdin  = core.stdc.stdio.stdin;
alias stdout = core.stdc.stdio.stdout;
alias stderr = core.stdc.stdio.stderr;

void writeln(string s)
{
    fwrite(s.ptr, 1, s.length, stdout);
    fwrite("\n".ptr, 1, 1, stdout);
}

void write(string s)
{
    fwrite(s.ptr, 1, s.length, stdout);
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


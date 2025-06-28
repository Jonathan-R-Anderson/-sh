module mstd.stdio;

import core.stdc.stdio;

alias File = FILE*;

File stdin  = core.stdc.stdio.stdin;
File stdout = core.stdc.stdio.stdout;
File stderr = core.stdc.stdio.stderr;

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


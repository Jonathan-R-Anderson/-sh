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

struct ByChunkRange
{
    File f;
    size_t chunkSize;
    ubyte[] buffer;
    bool done;

    this(File f, size_t chunkSize)
    {
        this.f = f;
        this.chunkSize = chunkSize;
        popFront();
    }

    @property bool empty() const { return done; }
    @property ubyte[] front() { return buffer; }

    void popFront()
    {
        if(done) return;
        if(buffer.length != chunkSize) buffer.length = chunkSize;
        auto n = fread(buffer.ptr, 1, chunkSize, f);
        buffer = buffer[0 .. n];
        if(n == 0) done = true;
    }
}

ByChunkRange byChunk(File f, size_t chunkSize)
{
    return ByChunkRange(f, chunkSize);
}

struct ByLineRange
{
    File f;
    string line;
    bool done;

    this(File f)
    {
        this.f = f;
        popFront();
    }

    @property bool empty() const { return done; }
    @property string front() { return line; }

    void popFront()
    {
        if(done) return;
        char[] buf;
        int c = fgetc(f);
        if(c == EOF)
        {
            done = true;
            line = null;
            return;
        }
        while(c != EOF && c != '\n')
        {
            buf ~= cast(char)c;
            c = fgetc(f);
        }
        line = cast(string)buf;
    }
}

ByLineRange byLine(File f)
{
    return ByLineRange(f);
}


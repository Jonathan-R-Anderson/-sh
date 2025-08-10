module ddrescue;

import mstd.stdio;
import mstd.file : exists, readText, append, write;
import mstd.conv : to;
import mstd.string : split, startsWith, toStringz;
import core.stdc.stdio : fopen, fclose, fseek, fread, fwrite, FILE, SEEK_SET;

size_t parseSize(string s)
{
    size_t mult = 1;
    if(s.length && (s[$-1] == 'K' || s[$-1] == 'k')) {
        mult = 1024;
        s = s[0 .. $-1];
    } else if(s.length && s[$-1] == 'M') {
        mult = 1024UL * 1024UL;
        s = s[0 .. $-1];
    } else if(s.length && s[$-1] == 'G') {
        mult = 1024UL * 1024UL * 1024UL;
        s = s[0 .. $-1];
    }
    return to!size_t(s) * mult;
}

void logEntry(string logFile, string entry)
{
    if(logFile.length)
        append(logFile, entry ~ "\n");
}

void ddrescueCommand(string[] tokens)
{
    size_t block = 512;
    size_t ipos = 0;
    size_t opos = 0;
    size_t maxSize = size_t.max;
    size_t maxErrors = size_t.max;
    int maxRetries = 0;
    string logFile;
    string infile;
    string outfile;
    bool verbose = false;

    size_t idx = 1;
    while(idx < tokens.length && startsWith(tokens[idx], "-")) {
        auto t = tokens[idx];
        if(startsWith(t, "-b=")) block = parseSize(t[3 .. $]);
        else if(startsWith(t, "--block-size=")) block = parseSize(t[13 .. $]);
        else if(startsWith(t, "-i=")) ipos = parseSize(t[3 .. $]);
        else if(startsWith(t, "--input-position=")) ipos = parseSize(t[17 .. $]);
        else if(startsWith(t, "-o=")) opos = parseSize(t[3 .. $]);
        else if(startsWith(t, "--output-position=")) opos = parseSize(t[18 .. $]);
        else if(startsWith(t, "-s=")) maxSize = parseSize(t[3 .. $]);
        else if(startsWith(t, "--max-size=")) maxSize = parseSize(t[11 .. $]);
        else if(startsWith(t, "-e=")) maxErrors = to!size_t(t[3 .. $]);
        else if(startsWith(t, "--max-errors=")) maxErrors = to!size_t(t[13 .. $]);
        else if(startsWith(t, "-r=")) maxRetries = to!int(t[3 .. $]);
        else if(startsWith(t, "--max-retries=")) maxRetries = to!int(t[14 .. $]);
        else if(t == "-v" || t == "--verbose") verbose = true;
        else if(t == "-q" || t == "--quiet") verbose = false;
        else break;
        idx++;
    }

    if(idx < tokens.length) { infile = tokens[idx]; idx++; }
    if(idx < tokens.length) { outfile = tokens[idx]; idx++; }
    if(idx < tokens.length) { logFile = tokens[idx]; idx++; }

    if(infile.length == 0 || outfile.length == 0) {
        writeln("Usage: ddrescue [options] infile outfile [logfile]");
        return;
    }

    FILE* fin = fopen(infile.toStringz(), "rb");
    if(fin is null) { writeln("ddrescue: cannot read " ~ infile); return; }

    FILE* fout;
    if(exists(outfile))
        fout = fopen(outfile.toStringz(), "r+b");
    else
        fout = fopen(outfile.toStringz(), "w+b");
    if(fout is null) { writeln("ddrescue: cannot write " ~ outfile); fclose(fin); return; }

    fseek(fin, cast(long)ipos, SEEK_SET);
    fseek(fout, cast(long)opos, SEEK_SET);

    ubyte[] buf;
    buf.length = block;

    size_t copied = 0;
    size_t errors = 0;

    while(copied < maxSize) {
        size_t toRead = block;
        if(copied + toRead > maxSize) toRead = maxSize - copied;
        size_t n = 0;
        bool readOk = false;
        foreach(i; 0 .. maxRetries + 1) {
            n = fread(buf.ptr, 1, toRead, fin);
            if(n == toRead) { readOk = true; break; }
            if(i == maxRetries) {
                errors++;
                logEntry(logFile, "error " ~ to!string(ipos) ~ " " ~ to!string(block));
                break;
            }
        }
        if(!readOk) {
            if(errors > maxErrors) break;
            ipos += block;
            opos += block;
            fseek(fin, cast(long)ipos, SEEK_SET);
            fseek(fout, cast(long)opos, SEEK_SET);
            copied += block;
            continue;
        }
        if(n == 0) break;
        fwrite(buf.ptr, 1, n, fout);
        logEntry(logFile, "ok " ~ to!string(ipos) ~ " " ~ to!string(n));
        ipos += n;
        opos += n;
        copied += n;
        if(n < toRead) break;
    }

    fclose(fin);
    fclose(fout);

    if(verbose)
        writeln("ddrescue: copied " ~ to!string(copied) ~ " bytes");
}

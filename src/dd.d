module dd;

import mstd.stdio;
import mstd.file : exists;
import mstd.conv : to;
import mstd.string : split, indexOf, endsWith, toStringz;
import core.stdc.stdio : fopen, fclose, fseek, fwrite, FILE, SEEK_SET;

size_t parseBytes(string s)
{
    size_t mult = 1;
    if(s.length >= 2 && (s.endsWith("KB") || s.endsWith("kB"))) {
        mult = 1000;
        s = s[0 .. $-2];
    } else if(s.length >= 2 && s.endsWith("MB")) {
        mult = 1000 * 1000;
        s = s[0 .. $-2];
    } else if(s.length >= 2 && s.endsWith("GB")) {
        mult = 1000UL * 1000UL * 1000UL;
        s = s[0 .. $-2];
    } else if(s.length && (s[$-1] == 'K' || s[$-1] == 'k')) {
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

void ddCommand(string[] tokens)
{
    string infile;
    string outfile;
    size_t bs = 512;
    size_t count = size_t.max;
    size_t skip = 0;
    size_t seek = 0;
    bool notrunc = false;

    foreach(t; tokens[1 .. $]) {
        auto idx = t.indexOf('=');
        if(idx < 0) continue;
        auto key = t[0 .. idx];
        auto val = t[idx+1 .. $];
        // Allow a default case, so a regular switch is required.
        switch(key) {
            case "if": infile = val; break;
            case "of": outfile = val; break;
            case "bs":
            case "ibs":
            case "obs":
                bs = parseBytes(val); break;
            case "count": count = to!size_t(val); break;
            case "skip":
            case "iseek":
                skip = to!size_t(val); break;
            case "seek":
            case "oseek":
                seek = to!size_t(val); break;
            case "conv":
                foreach(c; split(val, ","))
                    if(c == "notrunc") notrunc = true;
                break;
            default:
                break;
        }
    }

    FILE* fin;
    bool closeIn = true;
    if(infile.length == 0 || infile == "-") {
        fin = stdin;
        closeIn = false;
    } else {
        fin = fopen(infile.toStringz(), "rb");
        if(fin is null) { writeln("dd: cannot read " ~ infile); return; }
    }

    FILE* fout;
    bool closeOut = true;
    if(outfile.length == 0 || outfile == "-") {
        fout = stdout;
        closeOut = false;
    } else {
        if(notrunc) {
            if(exists(outfile))
                fout = fopen(outfile.toStringz(), "r+b");
            else
                fout = fopen(outfile.toStringz(), "w+b");
        } else {
            fout = fopen(outfile.toStringz(), "wb");
        }
        if(fout is null) { writeln("dd: cannot write " ~ outfile); if(closeIn) fclose(fin); return; }
    }

    if(skip > 0) {
        fseek(fin, cast(long)(skip * bs), SEEK_SET);
    }
    if(seek > 0) {
        fseek(fout, cast(long)(seek * bs), SEEK_SET);
    }

    size_t blocks = 0;
    foreach(chunk; byChunk(fin, bs)) {
        if(blocks >= count) break;
        fwrite(chunk.ptr, 1, chunk.length, fout);
        blocks++;
        if(chunk.length < bs) break;
    }

    if(closeIn) fclose(fin);
    if(closeOut) fclose(fout);
}


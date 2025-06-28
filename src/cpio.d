module cpio;

import std.stdio;
import std.file : read, write, dirEntries, SpanMode, mkdir, FileException,
                  isDir, getSize;
import std.conv : to;
import std.path : baseName;
import std.format : format;

struct Header {
    uint ino;
    uint mode;
    uint uid;
    uint gid;
    uint nlink;
    uint mtime;
    uint filesize;
    uint devmajor;
    uint devminor;
    uint rdevmajor;
    uint rdevminor;
    uint namesize;
}

void writeHeader(File f, string name, bool dir, ulong size) {
    Header h;
    h.ino = 0;
    h.mode = dir ? 0x41ED : 0x81A4;
    h.uid = 0;
    h.gid = 0;
    h.nlink = 1;
    h.mtime = cast(uint)Clock.currTime.toUnixTime;
    h.filesize = cast(uint)size;
    h.devmajor = 0;
    h.devminor = 0;
    h.rdevmajor = 0;
    h.rdevminor = 0;
    h.namesize = cast(uint)(name.length + 1);
    f.write("070701");
    foreach(field; [h.ino, h.mode, h.uid, h.gid, h.nlink, h.mtime,
                    h.filesize, h.devmajor, h.devminor, h.rdevmajor,
                    h.rdevminor, h.namesize, 0u])
    {
        f.write(format("%08X", field));
    }
    f.write(name);
    f.write('\0');
    while((f.tell % 4) != 0) f.write('\0');
}

void createArchive(string archive, string[] files) {
    auto fout = File(archive, "wb");
    foreach(path; files) {
        bool dir = isDir(path);
        auto name = baseName(path);
        ulong size = dir ? 0 : getSize(path);
        writeHeader(fout, name, dir, size);
        if(!dir)
            fout.rawWrite(read(path));
        while((fout.tell % 4) != 0) fout.write('\0');
    }
    // trailer
    fout.write("07070100000000000000000000000000000000000000000000000000000000000000000000000B00000000TRAILER!!!\0");
    while((fout.tell % 4) != 0) fout.write('\0');
    fout.close();
}

struct Entry {
    string name;
    bool isDir;
    ubyte[] data;
}

Entry[] readArchive(string archive) {
    Entry[] entries;
    auto f = File(archive, "rb");
    while(!f.eof) {
        auto magic = cast(string)f.read(6);
        if(magic.length == 0) break;
        auto rest = cast(string)f.read(104);
        if(magic != "070701") break;
        uint[13] fields;
        foreach(i; 0..13) {
            auto hex = rest[i*8 .. i*8+8];
            fields[i] = to!uint("0x" ~ hex);
        }
        auto namesize = fields[11];
        auto fname = cast(string)f.read(namesize);
        fname = fname[0 .. $-1];
        while((f.tell % 4) != 0) f.read(1);
        auto filesize = fields[6];
        ubyte[] content;
        if(filesize > 0) content = f.read(filesize);
        while((f.tell % 4) != 0) f.read(1);
        if(fname == "TRAILER!!!") break;
        entries ~= Entry(fname, (fields[2] & 0x4000) != 0, content);
    }
    f.close();
    return entries;
}

void extractArchive(string archive) {
    auto entries = readArchive(archive);
    foreach(e; entries) {
        if(e.isDir) {
            mkdir(e.name, 0755);
        } else {
            write(e.name, e.data);
        }
    }
}

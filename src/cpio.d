module cpio;

import core.stdc.stdio : FILE, fopen, fread, fwrite, fclose, ftell, fseek, feof, SEEK_SET;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : strlen, strcmp, memcmp;

// Entry structure for extracted files
struct Entry {
    const(char)* name;
    bool         isDir;
    ubyte*       data;
    uint         size;
}

// --- helpers ---

@safe nothrow @nogc
int hexNibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return 0;
}

@safe nothrow @nogc
uint hexToUint(const(char)* hex) {
    uint val = 0;
    foreach (i; 0 .. 8) {
        val = (val << 4) | cast(uint)hexNibble(hex[i]);
    }
    return val;
}

// Align stream to 4 bytes (newc format rule)
@nogc nothrow
void skipPad(FILE* f) {
    // ftell may be long; mod safely
    long pos = ftell(f);
    if (pos < 0) return;
    int rem = cast(int)(pos & 3);
    if (rem == 0) return;

    ubyte[3] trash; // read up to 3 bytes
    auto need = 4 - rem;
    fread(trash.ptr, 1, need, f);
}

// --- main I/O ---

// Read archive into array of entries
@nogc
int readArchive(const(char)* archive, Entry* outEntries, int maxEntries) {
    FILE* f = fopen(archive, "rb");
    if (!f) return 0;
    scope(exit) fclose(f);

    int count = 0;

    while (count < maxEntries) {
        // Read magic (6 chars + NUL)
        char[7] magic = void;
        if (fread(magic.ptr, 1, 6, f) != 6) break;
        magic[6] = '\0';

        // Only support 'newc' ("070701")
        if (memcmp(magic.ptr, "070701", 6) != 0) {
            // If we didn’t reach EOF, bail; otherwise we’re done
            break;
        }

        // There are 13 8-hex-digit fields = 104 bytes
        char[105] header = void;
        if (fread(header.ptr, 1, 104, f) != 104) break;
        header[104] = '\0';

        uint[13] fields = void;
        foreach (i; 0 .. 13) {
            fields[i] = hexToUint(header.ptr + (i * 8));
        }

        // Fields (newc): 0 ino,1 mode,2 uid,3 gid,4 nlink,5 mtime,
        // 6 filesize,7 devmajor,8 devminor,9 rdevmajor,10 rdevminor,
        // 11 namesize,12 check
        const uint namesize = fields[11];
        if (namesize == 0 || namesize > 1_000_000) break; // sanity

        // namesize includes trailing NUL
        auto name = cast(char*)malloc(namesize);
        if (!name) break;
        scope(failure) free(name);

        if (fread(name, 1, namesize, f) != namesize) {
            free(name);
            break;
        }
        // Ensure NUL (spec says last byte is NUL already)
        name[namesize - 1] = '\0';
        skipPad(f);

        if (strcmp(name, "TRAILER!!!") == 0) {
            free(name);
            break;
        }

        const uint filesize = fields[6];
        ubyte* buf = null;
        if (filesize) {
            buf = cast(ubyte*)malloc(filesize);
            if (!buf) {
                free(name);
                break;
            }
            if (fread(buf, 1, filesize, f) != filesize) {
                free(name);
                free(buf);
                break;
            }
        }
        skipPad(f);

        outEntries[count].name  = name;
        outEntries[count].isDir = (fields[1] & 0x4000) != 0; // S_IFDIR
        outEntries[count].data  = buf;
        outEntries[count].size  = filesize;
        ++count;
    }

    return count;
}

// Extract all files from archive to disk (basic libc I/O)
@nogc
void extractArchive(const(char)* archive) {
    Entry[128] entries = void; // adjust size as needed
    int n = readArchive(archive, entries.ptr, entries.length);

    foreach (i; 0 .. n) {
        auto e = entries[i];
        if (!e.isDir && e.data && e.size) {
            if (FILE* f = fopen(e.name, "wb")) {
                fwrite(e.data, 1, e.size, f);
                fclose(f);
            }
        }
        if (e.name) free(cast(void*)e.name);
        if (e.data) free(e.data);
    }
}

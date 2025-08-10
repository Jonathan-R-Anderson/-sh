module cpio;

extern(C):
import core.stdc.stdio : FILE, fopen, fread, fwrite, fclose, ftell, fseek, feof, SEEK_SET;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : strlen, strcmp, memcmp;
import mstd.string : toStringz;

// Entry structure for extracted files
struct Entry {
    const(char)* name;
    bool isDir;
    ubyte* data;
    uint size;
}

// Helper: convert 8-char hex string to uint
int hexToUint(const(char)* hex) {
    int val = 0;
    for (int i = 0; i < 8; i++) {
        val <<= 4;
        char c = hex[i];
        if (c >= '0' && c <= '9') val += c - '0';
        else if (c >= 'A' && c <= 'F') val += c - 'A' + 10;
    }
    return val;
}

// Helper: check if str starts with prefix
bool startsWith(const(char)* str, const(char)* prefix) {
    for (; *prefix; str++, prefix++) {
        if (*str != *prefix) return false;
    }
    return true;
}

// Helper: align to 4 bytes
void skipPad(FILE* f) {
    while ((ftell(f) % 4) != 0) {
        char discard;
        fread(&discard, 1, 1, f);
    }
}

// Read archive into array of entries
int readArchive(const(char)* archive, Entry* outEntries, int maxEntries) {
    FILE* f = fopen(archive, "rb");
    if (!f) return 0;

    int count = 0;
    while (!feof(f) && count < maxEntries) {
        char[7] magic = void;
        fread(magic.ptr, 1, 6, f);
        magic[6] = '\0';
        if (memcmp(magic.ptr, cast(const void*)"070701".ptr, 6) != 0) break;

        char[105] header = void;
        fread(header.ptr, 1, 104, f);

        uint[13] fields;
        for (int i = 0; i < 13; i++) {
            fields[i] = hexToUint(header.ptr + (i * 8));
        }

        uint namesize = fields[11];
        char* name = cast(char*)malloc(namesize);
        fread(name, 1, namesize, f);
        name[namesize - 1] = '\0';
        skipPad(f);

        if (strcmp(name, "TRAILER!!!") == 0) {
            free(name);
            break;
        }

        uint filesize = fields[6];
        ubyte* buf = null;
        if (filesize > 0) {
            buf = cast(ubyte*)malloc(filesize);
            fread(buf, 1, filesize, f);
        }
        skipPad(f);

        outEntries[count].name = name;
        outEntries[count].isDir = (fields[1] & 0x4000) != 0;
        outEntries[count].data = buf;
        outEntries[count].size = filesize;
        count++;
    }

    fclose(f);
    return count;
}

// Extract all files from archive to disk (requires basic libc I/O)
void extractArchive(const(char)* archive) {
    Entry[128] entries; // static array, adjust size as needed
    int n = readArchive(archive, entries.ptr, 128);
    for (int i = 0; i < n; i++) {
        auto e = entries[i];
        if (!e.isDir && e.data) {
            FILE* f = fopen(e.name, "wb");
            if (f) {
                fwrite(e.data, 1, e.size, f);
                fclose(f);
            }
        }
        free(cast(void*)e.name);
        if (e.data) free(e.data);
    }
}

// Create a very small "newc" cpio archive containing ``files``.  This
// implementation is intentionally minimal and only supports regular files.
void createArchive(string archive, string[] files)
{
    FILE* f = fopen(archive.toStringz(), "wb");
    if(!f) return;
    scope(exit) fclose(f);

    // Helper to write an 8-character hexadecimal field
    void writeHex(uint value)
    {
        char[8] buf;
        foreach_reverse(i; 0 .. 8)
        {
            uint v = value & 0xF;
            buf[i] = cast(char)(v < 10 ? '0' + v : 'A' + (v - 10));
            value >>= 4;
        }
        fwrite(buf.ptr, 1, 8, f);
    }

    import core.sys.posix.sys.stat : stat, stat_t, S_IFDIR;

    foreach(file; files)
    {
        stat_t sb;
        if(stat(file.toStringz(), &sb) != 0) continue;

        fwrite("070701".ptr, 1, 6, f);
        uint[13] fields;
        fields[0] = 0; // ino
        fields[1] = sb.st_mode;
        fields[2] = 0; // uid
        fields[3] = 0; // gid
        fields[4] = 1; // nlink
        fields[5] = cast(uint)sb.st_mtime;
        fields[6] = cast(uint)sb.st_size; // filesize
        fields[7] = fields[8] = fields[9] = fields[10] = 0; // dev fields
        fields[11] = cast(uint)(file.length + 1); // namesize including NUL
        fields[12] = 0; // check
        foreach(val; fields) writeHex(val);

        fwrite(file.ptr, 1, file.length, f);
        fwrite("\0".ptr, 1, 1, f);
        while((ftell(f) & 3) != 0) fwrite("\0".ptr, 1, 1, f);

        if(sb.st_size > 0 && (sb.st_mode & S_IFDIR) == 0)
        {
            FILE* rf = fopen(file.toStringz(), "rb");
            if(rf)
            {
                scope(exit) fclose(rf);
                ubyte[4096] buf;
                size_t n;
                while((n = fread(buf.ptr, 1, buf.length, rf)) > 0)
                    fwrite(buf.ptr, 1, n, f);
            }
        }
        while((ftell(f) & 3) != 0) fwrite("\0".ptr, 1, 1, f);
    }

    // Write trailer entry
    fwrite("070701".ptr, 1, 6, f);
    uint[13] endFields = [0,0,0,0,0,0,0,0,0,0,0,11,0];
    foreach(val; endFields) writeHex(val);
    fwrite("TRAILER!!!\0".ptr, 1, 11, f);
    while((ftell(f) & 3) != 0) fwrite("\0".ptr, 1, 1, f);
}

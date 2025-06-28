module cpio;

extern(C):
import core.stdc.stdio : FILE, fopen, fread, fwrite, fclose, ftell, fseek, SEEK_SET;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : strlen, strcmp, memcmp;

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
        if (memcmp(magic.ptr, "070701", 6) != 0) break;

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

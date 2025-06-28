module cpio;

extern(C):

// C headers
import core.stdc.stdio : FILE, fopen, fclose, fread, fwrite, fseek, ftell, SEEK_SET, SEEK_END;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memcmp;
import core.stdc.time : time_t, time;

// Helpers
uint hexToUint(const(char)* hex) {
    uint result = 0;
    foreach (i; 0 .. 8) {
        result <<= 4;
        char c = hex[i];
        if (c >= '0' && c <= '9') result |= cast(uint)(c - '0');
        else if (c >= 'A' && c <= 'F') result |= cast(uint)(c - 'A' + 10);
    }
    return result;
}

void pad(FILE* f) {
    while ((ftell(f) % 4) != 0) {
        static char zero = 0;
        fwrite(&zero, 1, 1, f);
    }
}

void writeHeader(FILE* f, const(char)* name, bool isDir, uint size) {
    const char[7] magic = "070701";
    fwrite(magic.ptr, 1, 6, f);

    uint[13] fields = [
        0,                       // ino
        isDir ? 0x41ED : 0x81A4, // mode
        0, 0,                    // uid, gid
        1,                       // nlink
        cast(uint)time(null),   // mtime
        size, 0, 0, 0, 0,        // size, devs
        cast(uint)(strlen(name) + 1), // namesize
        0                        // check
    ];

    foreach (field; fields) {
        char[9] hex = void;
        foreach_reverse (i; 0 .. 8) {
            auto digit = field & 0xF;
            hex[i] = cast(char)(digit < 10 ? digit + '0' : digit - 10 + 'A');
            field >>= 4;
        }
        fwrite(hex.ptr, 1, 8, f);
    }

    fwrite(name, 1, strlen(name) + 1, f);
    pad(f);
}

void createArchive(const(char)* archive, const(char)** paths, int count) {
    FILE* f = fopen(archive, "wb");
    if (!f) return;

    foreach (i; 0 .. count) {
        const(char)* name = paths[i];

        FILE* file = fopen(name, "rb");
        bool isDir = (file is null);
        uint size = 0;

        if (!isDir) {
            fseek(file, 0, SEEK_END);
            size = cast(uint)ftell(file);
            fseek(file, 0, SEEK_SET);
        }

        writeHeader(f, name, isDir, size);

        if (!isDir) {
            ubyte* buf = cast(ubyte*)malloc(size);
            if (buf) {
                fread(buf, 1, size, file);
                fwrite(buf, 1, size, f);
                free(buf);
            }
            fclose(file);
        }
        pad(f);
    }

    // Write trailer
    const char[18] trailerName = "TRAILER!!!\0";
    writeHeader(f, trailerName.ptr, false, 0);
    fclose(f);
}

extern (D) void main() {} // Stub entry point (or define your interface here)

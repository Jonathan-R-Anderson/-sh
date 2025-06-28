module mstd.file;

// Import POSIX filesystem helpers.  Alias `getcwd` to avoid colliding with the
// wrapper function defined below.
public import core.sys.posix.unistd : chdir, posix_getcwd = getcwd, symlink, readlink, unlink;
import core.sys.posix.dirent : DIR, dirent, opendir, readdir, closedir;
import core.sys.posix.fcntl : open, O_RDONLY, O_WRONLY, O_CREAT, O_TRUNC, O_APPEND;
import core.sys.posix.sys.stat : stat, lstat, S_IFDIR, S_IFREG;
// Use POSIX versions of directory creation/removal under different names to
// keep the API small and easy to implement in `betterC` builds.
import core.sys.posix.sys.stat : posix_mkdir = mkdir, posix_rmdir = rmdir;
import core.stdc.stdlib : malloc, free;
import core.stdc.stdio : fopen, fclose, fread, fwrite;
import core.stdc.string : strlen;

struct DirEntry { string name; }

enum SpanMode { shallow, depth }

DirEntry[] dirEntries(string path, SpanMode mode = SpanMode.shallow)
{
    DirEntry[] result;
    auto d = opendir(path.toStringz());
    if(d is null) return result;
    scope(exit) closedir(d);
    dirent* entry;
    while((entry = readdir(d)) !is null)
    {
        auto name = entry.d_name[0 .. strlen(entry.d_name.ptr)].idup;
        if(name == "." || name == "..") continue;
        result ~= DirEntry(name);
    }
    return result;
}

string getcwd()
{
    char[4096] buf;
    auto p = posix_getcwd(buf.ptr, buf.length);
    return p ? buf[0 .. strlen(p)].idup : "";
}

bool exists(string path)
{
    stat sb;
    return stat(path.toStringz(), &sb) == 0;
}

bool isFile(string path)
{
    stat sb; if(stat(path.toStringz(), &sb) != 0) return false; return (sb.st_mode & S_IFREG) != 0;
}

bool isDir(string path)
{
    stat sb; if(stat(path.toStringz(), &sb) != 0) return false; return (sb.st_mode & S_IFDIR) != 0;
}

string readText(string path)
{
    auto f = fopen(path.toStringz(), "rb");
    if(f is null) return "";
    scope(exit) fclose(f);
    char[] data;
    ubyte[4096] buf;
    size_t n;
    while((n = fread(buf.ptr, 1, buf.length, f)) > 0)
        data ~= cast(char[])buf[0 .. n];
    return data.idup;
}

void write(string path, const(char)[] data)
{
    auto f = fopen(path.toStringz(), "wb");
    if(f is null) return;
    scope(exit) fclose(f);
    fwrite(data.ptr, 1, data.length, f);
}

void append(string path, const(char)[] data)
{
    auto f = fopen(path.toStringz(), "ab");
    if(f is null) return;
    scope(exit) fclose(f);
    fwrite(data.ptr, 1, data.length, f);
}

void remove(string path)
{
    unlink(path.toStringz());
}

void copy(string src, string dst)
{
    auto content = readText(src);
    write(dst, content);
}

void rename(string src, string dst)
{
    import core.sys.posix.unistd : posix_rename = rename;
    posix_rename(src.toStringz(), dst.toStringz());
}

string read(string path)
{
    return readText(path);
}

string readLink(string path)
{
    char[4096] buf;
    auto len = readlink(path.toStringz(), buf.ptr, buf.length - 1);
    if(len < 0) return "";
    return buf[0 .. len].idup;
}


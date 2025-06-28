module mstd.process;

string[string] environment;

static this()
{
    // populate from OS environment if available
    version(Posix)
    {
        import core.stdc.stdlib : environ;
        size_t i = 0;
        while(environ[i])
        {
            import mstd.string : split, toStringz;
            auto pair = split(environ[i].fromStringz, "=");
            if(pair.length >= 2)
                environment[pair[0]] = pair[1];
            ++i;
        }
    }
}

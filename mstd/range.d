module mstd.range;

struct Iota
{
    int start;
    int stop;

    bool empty() const { return start >= stop; }
    int front() const { return start; }
    void popFront() { ++start; }
}

Iota iota(int start, int stop)
{
    return Iota(start, stop);
}

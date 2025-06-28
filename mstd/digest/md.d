module mstd.digest.md;

// Minimal MD5 implementation in D based on RFC 1321.
import core.stdc.string : memcpy;

struct MD5State
{
    uint[4] a = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476];
    ulong length = 0; // message length in bits
    ubyte[64] buffer;
    size_t bufLen = 0;
}

private uint F(uint x, uint y, uint z) { return (x & y) | (~x & z); }
private uint G(uint x, uint y, uint z) { return (x & z) | (y & ~z); }
private uint H(uint x, uint y, uint z) { return x ^ y ^ z; }
private uint I(uint x, uint y, uint z) { return y ^ (x | ~z); }
private uint rotl(uint x, uint n) { return (x << n) | (x >> (32 - n)); }

private void transform(ref MD5State st, const(ubyte)* block)
{
    uint a = st.a[0];
    uint b = st.a[1];
    uint c = st.a[2];
    uint d = st.a[3];
    uint[16] x;
    foreach(i; 0 .. 16)
        x[i] = block[i*4] | (block[i*4+1]<<8) | (block[i*4+2]<<16) | (block[i*4+3]<<24);

    enum S11=7; enum S12=12; enum S13=17; enum S14=22;
    enum S21=5; enum S22=9;  enum S23=14; enum S24=20;
    enum S31=4; enum S32=11; enum S33=16; enum S34=23;
    enum S41=6; enum S42=10; enum S43=15; enum S44=21;

    // Round 1
    a = rotl(a + F(b,c,d) + x[0]  + 0xd76aa478, S11) + b;
    d = rotl(d + F(a,b,c) + x[1]  + 0xe8c7b756, S12) + a;
    c = rotl(c + F(d,a,b) + x[2]  + 0x242070db, S13) + d;
    b = rotl(b + F(c,d,a) + x[3]  + 0xc1bdceee, S14) + c;
    a = rotl(a + F(b,c,d) + x[4]  + 0xf57c0faf, S11) + b;
    d = rotl(d + F(a,b,c) + x[5]  + 0x4787c62a, S12) + a;
    c = rotl(c + F(d,a,b) + x[6]  + 0xa8304613, S13) + d;
    b = rotl(b + F(c,d,a) + x[7]  + 0xfd469501, S14) + c;
    a = rotl(a + F(b,c,d) + x[8]  + 0x698098d8, S11) + b;
    d = rotl(d + F(a,b,c) + x[9]  + 0x8b44f7af, S12) + a;
    c = rotl(c + F(d,a,b) + x[10] + 0xffff5bb1, S13) + d;
    b = rotl(b + F(c,d,a) + x[11] + 0x895cd7be, S14) + c;
    a = rotl(a + F(b,c,d) + x[12] + 0x6b901122, S11) + b;
    d = rotl(d + F(a,b,c) + x[13] + 0xfd987193, S12) + a;
    c = rotl(c + F(d,a,b) + x[14] + 0xa679438e, S13) + d;
    b = rotl(b + F(c,d,a) + x[15] + 0x49b40821, S14) + c;

    // Round 2
    a = rotl(a + G(b,c,d) + x[1]  + 0xf61e2562, S21) + b;
    d = rotl(d + G(a,b,c) + x[6]  + 0xc040b340, S22) + a;
    c = rotl(c + G(d,a,b) + x[11] + 0x265e5a51, S23) + d;
    b = rotl(b + G(c,d,a) + x[0]  + 0xe9b6c7aa, S24) + c;
    a = rotl(a + G(b,c,d) + x[5]  + 0xd62f105d, S21) + b;
    d = rotl(d + G(a,b,c) + x[10] + 0x02441453, S22) + a;
    c = rotl(c + G(d,a,b) + x[15] + 0xd8a1e681, S23) + d;
    b = rotl(b + G(c,d,a) + x[4]  + 0xe7d3fbc8, S24) + c;
    a = rotl(a + G(b,c,d) + x[9]  + 0x21e1cde6, S21) + b;
    d = rotl(d + G(a,b,c) + x[14] + 0xc33707d6, S22) + a;
    c = rotl(c + G(d,a,b) + x[3]  + 0xf4d50d87, S23) + d;
    b = rotl(b + G(c,d,a) + x[8]  + 0x455a14ed, S24) + c;
    a = rotl(a + G(b,c,d) + x[13] + 0xa9e3e905, S21) + b;
    d = rotl(d + G(a,b,c) + x[2]  + 0xfcefa3f8, S22) + a;
    c = rotl(c + G(d,a,b) + x[7]  + 0x676f02d9, S23) + d;
    b = rotl(b + G(c,d,a) + x[12] + 0x8d2a4c8a, S24) + c;

    // Round 3
    a = rotl(a + H(b,c,d) + x[5]  + 0xfffa3942, S31) + b;
    d = rotl(d + H(a,b,c) + x[8]  + 0x8771f681, S32) + a;
    c = rotl(c + H(d,a,b) + x[11] + 0x6d9d6122, S33) + d;
    b = rotl(b + H(c,d,a) + x[14] + 0xfde5380c, S34) + c;
    a = rotl(a + H(b,c,d) + x[1]  + 0xa4beea44, S31) + b;
    d = rotl(d + H(a,b,c) + x[4]  + 0x4bdecfa9, S32) + a;
    c = rotl(c + H(d,a,b) + x[7]  + 0xf6bb4b60, S33) + d;
    b = rotl(b + H(c,d,a) + x[10] + 0xbebfbc70, S34) + c;
    a = rotl(a + H(b,c,d) + x[13] + 0x289b7ec6, S31) + b;
    d = rotl(d + H(a,b,c) + x[0]  + 0xeaa127fa, S32) + a;
    c = rotl(c + H(d,a,b) + x[3]  + 0xd4ef3085, S33) + d;
    b = rotl(b + H(c,d,a) + x[6]  + 0x04881d05, S34) + c;
    a = rotl(a + H(b,c,d) + x[9]  + 0xd9d4d039, S31) + b;
    d = rotl(d + H(a,b,c) + x[12] + 0xe6db99e5, S32) + a;
    c = rotl(c + H(d,a,b) + x[15] + 0x1fa27cf8, S33) + d;
    b = rotl(b + H(c,d,a) + x[2]  + 0xc4ac5665, S34) + c;

    // Round 4
    a = rotl(a + I(b,c,d) + x[0]  + 0xf4292244, S41) + b;
    d = rotl(d + I(a,b,c) + x[7]  + 0x432aff97, S42) + a;
    c = rotl(c + I(d,a,b) + x[14] + 0xab9423a7, S43) + d;
    b = rotl(b + I(c,d,a) + x[5]  + 0xfc93a039, S44) + c;
    a = rotl(a + I(b,c,d) + x[12] + 0x655b59c3, S41) + b;
    d = rotl(d + I(a,b,c) + x[3]  + 0x8f0ccc92, S42) + a;
    c = rotl(c + I(d,a,b) + x[10] + 0xffeff47d, S43) + d;
    b = rotl(b + I(c,d,a) + x[1]  + 0x85845dd1, S44) + c;
    a = rotl(a + I(b,c,d) + x[8]  + 0x6fa87e4f, S41) + b;
    d = rotl(d + I(a,b,c) + x[15] + 0xfe2ce6e0, S42) + a;
    c = rotl(c + I(d,a,b) + x[6]  + 0xa3014314, S43) + d;
    b = rotl(b + I(c,d,a) + x[13] + 0x4e0811a1, S44) + c;
    a = rotl(a + I(b,c,d) + x[4]  + 0xf7537e82, S41) + b;
    d = rotl(d + I(a,b,c) + x[11] + 0xbd3af235, S42) + a;
    c = rotl(c + I(d,a,b) + x[2]  + 0x2ad7d2bb, S43) + d;
    b = rotl(b + I(c,d,a) + x[9]  + 0xeb86d391, S44) + c;

    st.a[0] += a;
    st.a[1] += b;
    st.a[2] += c;
    st.a[3] += d;
}

void update(ref MD5State st, const(ubyte)[] data)
{
    size_t i = 0;
    st.length += data.length * 8;
    if(st.bufLen > 0)
    {
        size_t need = 64 - st.bufLen;
        if(data.length >= need)
        {
            memcpy(st.buffer.ptr + st.bufLen, data.ptr, need);
            transform(st, st.buffer.ptr);
            st.bufLen = 0;
            i = need;
        }
        else
        {
            memcpy(st.buffer.ptr + st.bufLen, data.ptr, data.length);
            st.bufLen += data.length;
            return;
        }
    }
    for(; i + 63 < data.length; i += 64)
        transform(st, data.ptr + i);
    auto remain = data.length - i;
    if(remain > 0)
    {
        memcpy(st.buffer.ptr, data.ptr + i, remain);
        st.bufLen = remain;
    }
}

ubyte[16] finish(ref MD5State st)
{
    ubyte[64] pad = 0;
    pad[0] = 0x80;
    size_t padLen = (st.bufLen < 56) ? (56 - st.bufLen) : (120 - st.bufLen);
    update(st, pad[0 .. padLen]);
    ubyte[8] lenBytes;
    foreach(i; 0 .. 8)
        lenBytes[i] = cast(ubyte)((st.length >> (i*8)) & 0xff);
    update(st, lenBytes[0 .. 8]);
    ubyte[16] digest;
    foreach(i; 0 .. 4)
    {
        digest[i*4]   = cast(ubyte)(st.a[i] & 0xff);
        digest[i*4+1] = cast(ubyte)((st.a[i] >> 8) & 0xff);
        digest[i*4+2] = cast(ubyte)((st.a[i] >> 16) & 0xff);
        digest[i*4+3] = cast(ubyte)((st.a[i] >> 24) & 0xff);
    }
    return digest;
}

/// Convenience function computing MD5 of data.
ubyte[16] md5Of(const(ubyte)[] data)
{
    MD5State st;
    update(st, data);
    return finish(st);
}

/*
 * zlib gzip wrapper for http-pixiu
 * Compiles to a shared object and is loaded via Chez Scheme FFI.
 *
 * Build:
 *   gcc -shared -fPIC -o zlib-gzip-wrapper.so zlib-gzip.c -lz
 */

#include <zlib.h>
#include <stdlib.h>
#include <string.h>

int http_pixiu_gzip_compress(const unsigned char* src, size_t src_len,
                              unsigned char* dst, size_t* dst_len,
                              int level) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef*)src;
    strm.avail_in = (uInt)src_len;
    strm.next_out = dst;
    strm.avail_out = (uInt)(*dst_len);

    int ret = deflateInit2(&strm, level, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
    if (ret != Z_OK) return ret;

    ret = deflate(&strm, Z_FINISH);
    if (ret != Z_STREAM_END) {
        deflateEnd(&strm);
        return ret;
    }

    *dst_len = strm.total_out;
    deflateEnd(&strm);
    return Z_OK;
}

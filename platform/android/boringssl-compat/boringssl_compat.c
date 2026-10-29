/*
 * BoringSSL 兼容垫片
 *
 * FFmpeg 8 的 libavformat/tls_openssl.c 在 DTLS 分支调用 DTLS_get_data_mtu()，
 * 该函数是 OpenSSL 1.1.1+ 提供、BoringSSL 未实现的。这里按 RFC 6347 的典型
 * 取值返回一个保守 MTU（1200），保证链接通过且 DTLS 行为合理。
 */
#include <stddef.h>
#include <openssl/ssl.h>

size_t DTLS_get_data_mtu(const SSL *ssl)
{
    (void)ssl;
    return 1200;
}

void DTLS_set_link_mtu(SSL *ssl, size_t mtu)
{
    (void)ssl;
    (void)mtu;
}

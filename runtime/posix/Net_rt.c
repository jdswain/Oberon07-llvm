/* Net_rt.c — POSIX socket strong overrides for Net.Mod (DDR-015/016).
 *
 * A thin skin over getaddrinfo/socket/bind/listen/accept/connect/recv/send/
 * close. Each Oberon *Raw stub in Net.Mod has weak linkage; these strong
 * definitions win at link time. The Oberon side owns the interfaces, the
 * addressing strings and the accept loop; this file owns only the syscalls.
 *
 * ABI: an Oberon `ARRAY OF CHAR`/`ARRAY OF BYTE` parameter arrives as a
 * (pointer, length) pair; a `VAR INTEGER` as `int *`; an `INTEGER` as `int`.
 * The CHAR arrays are NUL-terminated by the Oberon caller, so `len` is the
 * buffer capacity, used only to bound writes back.
 */
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

/* Don't die with SIGPIPE when a peer closes mid-write. */
static void ignore_sigpipe(void) {
    static int done = 0;
    if (!done) { signal(SIGPIPE, SIG_IGN); done = 1; }
}

static void set_nosigpipe(int s) {
#ifdef SO_NOSIGPIPE
    int on = 1;
    setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#else
    (void)s;
#endif
}

/* Render a sockaddr as "host:port" into out (NUL-terminated, bounded). */
static void fmt_addr(struct sockaddr *sa, socklen_t sl, char *out, int outlen) {
    char host[NI_MAXHOST], serv[NI_MAXSERV];
    if (outlen <= 0) return;
    out[0] = 0;
    if (getnameinfo(sa, sl, host, sizeof host, serv, sizeof serv,
                    NI_NUMERICHOST | NI_NUMERICSERV) == 0) {
        snprintf(out, outlen, "%s:%s", host, serv);
    }
}

void Net__DialRaw(const char *host, int hlen, const char *port, int plen,
                  int *fd, int *res) {
    struct addrinfo hints, *ai, *p;
    const char *node;
    int s = -1, rc;
    (void)hlen; (void)plen;
    ignore_sigpipe();
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    node = (host && host[0]) ? host : NULL;
    rc = getaddrinfo(node, port, &hints, &ai);
    if (rc != 0) { *fd = -1; *res = EINVAL; return; }
    for (p = ai; p != NULL; p = p->ai_next) {
        s = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (s < 0) continue;
        set_nosigpipe(s);
        if (connect(s, p->ai_addr, p->ai_addrlen) == 0) break;
        close(s); s = -1;
    }
    freeaddrinfo(ai);
    if (s < 0) { *fd = -1; *res = errno ? errno : ECONNREFUSED; }
    else { *fd = s; *res = 0; }
}

void Net__ListenRaw(const char *host, int hlen, const char *port, int plen,
                    int *fd, int *res) {
    struct addrinfo hints, *ai, *p;
    const char *node;
    int s = -1, rc, on = 1;
    (void)hlen; (void)plen;
    ignore_sigpipe();
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_PASSIVE;
    node = (host && host[0]) ? host : NULL;
    rc = getaddrinfo(node, port, &hints, &ai);
    if (rc != 0) { *fd = -1; *res = EINVAL; return; }
    for (p = ai; p != NULL; p = p->ai_next) {
        s = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (s < 0) continue;
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
        if (bind(s, p->ai_addr, p->ai_addrlen) == 0 && listen(s, 16) == 0) break;
        close(s); s = -1;
    }
    freeaddrinfo(ai);
    if (s < 0) { *fd = -1; *res = errno ? errno : EADDRINUSE; }
    else { *fd = s; *res = 0; }
}

void Net__AcceptRaw(int lfd, int *fd, int *res, char *peer, int peer_len) {
    struct sockaddr_storage ss;
    socklen_t sl = sizeof ss;
    int s;
    if (peer_len > 0) peer[0] = 0;
    do { s = accept(lfd, (struct sockaddr *)&ss, &sl); }
    while (s < 0 && errno == EINTR);
    if (s < 0) { *fd = -1; *res = errno ? errno : EIO; return; }
    set_nosigpipe(s);
    *fd = s; *res = 0;
    fmt_addr((struct sockaddr *)&ss, sl, peer, peer_len);
}

int Net__ReadRaw(int fd, uint8_t *buf, int buf_len, int n) {
    ssize_t r;
    int m = (n < buf_len) ? n : buf_len;
    if (m < 0) m = 0;
    do { r = recv(fd, buf, (size_t)m, 0); } while (r < 0 && errno == EINTR);
    return (int)r;
}

int Net__WriteRaw(int fd, uint8_t *buf, int buf_len, int n) {
    ssize_t w;
    int m = (n < buf_len) ? n : buf_len;
    if (m < 0) m = 0;
    do { w = send(fd, buf, (size_t)m, MSG_NOSIGNAL); }
    while (w < 0 && errno == EINTR);
    return (int)w;
}

void Net__CloseRaw(int fd) {
    if (fd >= 0) close(fd);
}

void Net__LocalAddrRaw(int fd, char *a, int a_len) {
    struct sockaddr_storage ss;
    socklen_t sl = sizeof ss;
    if (a_len > 0) a[0] = 0;
    if (getsockname(fd, (struct sockaddr *)&ss, &sl) == 0) {
        fmt_addr((struct sockaddr *)&ss, sl, a, a_len);
    }
}

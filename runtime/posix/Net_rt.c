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
#include <fcntl.h>
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

/* Runtime I/O-wait seam (runtime.c): block until fd is ready, cooperatively
   yielding to other tasks when the Tasks scheduler is linked, else poll().
   want: bit0 = readable, bit1 = writable. */
extern int oc_iowait(int fd, int want);
#define IOWAIT_READ  1
#define IOWAIT_WRITE 2

static void set_nonblock(int s) {
    int fl = fcntl(s, F_GETFL, 0);
    if (fl >= 0) fcntl(s, F_SETFL, fl | O_NONBLOCK);
}

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
        int r;
        s = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (s < 0) continue;
        set_nosigpipe(s);
        set_nonblock(s);
        r = connect(s, p->ai_addr, p->ai_addrlen);
        if (r == 0) break;                       /* immediate (loopback) */
        if (errno == EINPROGRESS) {              /* wait writable, check SO_ERROR */
            int soerr = 0;
            socklen_t sl = sizeof soerr;
            oc_iowait(s, IOWAIT_WRITE);
            if (getsockopt(s, SOL_SOCKET, SO_ERROR, &soerr, &sl) == 0 && soerr == 0) break;
            errno = soerr ? soerr : ECONNREFUSED;
        }
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
    else { set_nonblock(s); *fd = s; *res = 0; }
}

void Net__AcceptRaw(int lfd, int *fd, int *res, char *peer, int peer_len) {
    struct sockaddr_storage ss;
    socklen_t sl = sizeof ss;
    int s;
    if (peer_len > 0) peer[0] = 0;
    for (;;) {
        s = accept(lfd, (struct sockaddr *)&ss, &sl);
        if (s >= 0) break;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) { oc_iowait(lfd, IOWAIT_READ); continue; }
        *fd = -1; *res = errno ? errno : EIO; return;
    }
    set_nosigpipe(s);
    set_nonblock(s);
    *fd = s; *res = 0;
    fmt_addr((struct sockaddr *)&ss, sl, peer, peer_len);
}

/* Clamp a (start, len) window to [0, buf_len]; returns the byte count and
 * leaves *off at the (bounded) start so the window is buf + *off, m bytes. */
static int clamp_window(int buf_len, int start, int len, int *off) {
    int avail, m;
    if (start < 0) start = 0;
    if (start > buf_len) start = buf_len;
    avail = buf_len - start;
    m = (len < avail) ? len : avail;
    if (m < 0) m = 0;
    *off = start;
    return m;
}

int Net__ReadRaw(int fd, uint8_t *buf, int buf_len, int start, int len) {
    ssize_t r;
    int off, m = clamp_window(buf_len, start, len, &off);
    for (;;) {
        r = recv(fd, buf + off, (size_t)m, 0);
        if (r >= 0) break;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) { oc_iowait(fd, IOWAIT_READ); continue; }
        break;
    }
    return (int)r;
}

int Net__WriteRaw(int fd, uint8_t *buf, int buf_len, int start, int len) {
    ssize_t w;
    int off, m = clamp_window(buf_len, start, len, &off);
    for (;;) {
        w = send(fd, buf + off, (size_t)m, MSG_NOSIGNAL);
        if (w >= 0) break;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) { oc_iowait(fd, IOWAIT_WRITE); continue; }
        break;
    }
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

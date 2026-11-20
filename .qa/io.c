#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static unsigned long long tx, rx, nt, nr;
static int port_of(const struct sockaddr *a) {
    if (!a) return 0;
    if (a->sa_family == AF_INET) return ntohs(((const struct sockaddr_in *)a)->sin_port);
    if (a->sa_family == AF_INET6) return ntohs(((const struct sockaddr_in6 *)a)->sin6_port);
    return 0;
}
static void account(int fd, ssize_t n, const struct sockaddr *a, int sending) {
    if (n < 0 || !a || !getenv("MATCH_ROLE")) return;
    int old_errno = errno;
    int port = port_of(a);
    if (port != 18921) {
        struct sockaddr_storage self;
        socklen_t len = sizeof self;
        if (getsockname(fd, (struct sockaddr *)&self, &len) != 0 || port_of((struct sockaddr *)&self) != 18921) {
            errno = old_errno; return;
        }
    }
    if (sending) { __atomic_fetch_add(&tx,n,__ATOMIC_RELAXED); __atomic_fetch_add(&nt,1,__ATOMIC_RELAXED); }
    else { __atomic_fetch_add(&rx,n,__ATOMIC_RELAXED); __atomic_fetch_add(&nr,1,__ATOMIC_RELAXED); }
    errno = old_errno;
}
ssize_t sendmsg(int fd,const struct msghdr *m,int f) {
    static ssize_t (*real)(int,const struct msghdr *,int);
    if(!real) real=dlsym(RTLD_NEXT,"sendmsg");
    ssize_t n=real(fd,m,f); account(fd,n,m?m->msg_name:NULL,1); return n;
}
ssize_t recvmsg(int fd,struct msghdr *m,int f) {
    static ssize_t (*real)(int,struct msghdr *,int);
    if(!real) real=dlsym(RTLD_NEXT,"recvmsg");
    ssize_t n=real(fd,m,f); if(!(f & MSG_PEEK)) account(fd,n,m?m->msg_name:NULL,0); return n;
}
ssize_t sendto(int fd,const void *b,size_t l,int f,const struct sockaddr *a,socklen_t sz) {
    static ssize_t (*real)(int,const void *,size_t,int,const struct sockaddr *,socklen_t);
    if(!real) real=dlsym(RTLD_NEXT,"sendto");
    ssize_t n=real(fd,b,l,f,a,sz); account(fd,n,a,1); return n;
}
ssize_t recvfrom(int fd,void *b,size_t l,int f,struct sockaddr *a,socklen_t *sz) {
    static ssize_t (*real)(int,void *,size_t,int,struct sockaddr *,socklen_t *);
    if(!real) real=dlsym(RTLD_NEXT,"recvfrom");
    ssize_t n=real(fd,b,l,f,a,sz); if(!(f & MSG_PEEK)) account(fd,n,a,0); return n;
}
__attribute__((destructor)) static void report(void) {
    const char *role=getenv("MATCH_ROLE");
    if(role) fprintf(stderr,"[UDP_IO] role=%s tx=%llu rx=%llu packets_tx=%llu packets_rx=%llu\n",role,tx,rx,nt,nr);
}

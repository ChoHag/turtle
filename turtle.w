@i types.w

@** TurTle.

@<Macros...@>=
#ifdef __GNUC__
#define unused __attribute__ ((__unused__))
#else
#define unused
#endif

@ @c
#include <sys/queue.h>
#include <sys/uio.h>
@#
#include <assert.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
@#
#include <matrix.h>
#include <event.h>
#include <imsg.h>
#include "cgl-opengl.h"
@#
#include "turtle.h"
#include "io.h"
#include "term.h"
#include "cgl.h"
@#
@<Global variables@>@;

@ @(turtle.h@>=
#ifndef TURTLE_H
#define TURTLE_H
@h
#include <stdbool.h>
@<Macros and other shared definitions@>@;
@<Exported variables@>@;
@<Public function declarations@>@;
#endif /* |TURTLE_H| */

@ @<Global...@>=
struct timespec   hz_sim = { 0, 1000000000 / 2 };
struct event      tick_sim;

struct timeval    vhz_sim;
struct timespec   real_clock, sim_clock, hz2_sim;

int64_t sim_tick = 0;
int64_t sim_instance = 0x100;

#define TL_REFRESH_NSEC (1000000000ll / 32) /* 31.25Hz */

bool Debug = true;
bool Verbose = true;

char *Win_Name = NULL;

@ @<Export...@>=
extern bool Debug, Verbose;
extern char *Win_Name;

@ @<Pub...@>=
void tock_turtle (int, short, void *);

@ @<Global...@>=
char *malloc_options = "SX"; /* Enable |malloc| security features,
                                        abort on allocation failure. */

@ @c
int
main (int    argc,
      char **argv)
{
        char *n;

        event_init();

        n = argv[0];
        while ((n = strchr(n + 1, '/')))
                Win_Name = n + 1;

        io_init(80, 25, 12, TL_REFRESH_NSEC); /* Calls |cgl_init|. */
        term_init(80, 25);

        clock_gettime(CLOCK_MONOTONIC, &real_clock);

        event_dispatch();

        io_terminate();

        return 0;
}

@ @c
void
tock_turtle (int    fd,
             short  events,
             void  *arg    unused)
{
        struct timespec log_start, log_io, log_blit;

        assert(fd == -1);
        assert(events & EV_TIMEOUT);

        clock_gettime(CLOCK_MONOTONIC, &log_start);
        term_draw();
        clock_gettime(CLOCK_MONOTONIC, &log_blit);
        io_events(); // move to fd event
        clock_gettime(CLOCK_MONOTONIC, &log_io);
        io_reset_clock(&log_start);

        real_clock = log_start;
}

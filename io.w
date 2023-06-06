@i types.w

@** Input \AM\ Output. This document describes the routines for
communicating with other processes and with human users.

@c
#include <assert.h>
#include <err.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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
@<IO global variables@>@;
@<IO private functions@>@;

@ @(io.h@>=
#ifndef TRTIO_H
#define TRTIO_H
@h
#include <sys/time.h>
@<IO function declarations@>@;
#endif /* |TRTIO_H| */

@ @<IO global...@>=
struct {
        struct timespec m;
        struct timeval  n;
} Win_Hz;
struct event Win_Clock;

struct event Event_SIGABRT, Event_SIGINT, Event_SIGQUIT, Event_SIGTERM;
struct bufferevent *Event_STDIN = NULL;

@ @<IO fun...@>=
void io_events (void);
void io_init (int, int, int, long);
void io_reset_clock (struct timespec *);
void io_stop (void);
void io_terminate (void);

@ @<IO private...@>=
static void io_stdio_error (struct bufferevent *, short, void *);
static void io_sighook (int, short, void *);
static void io_stdio_read (struct bufferevent *, void *);

@ @c
void
io_init (int  w,
         int  h,
         int  s,
         long rhythm)
{
        signal_set(&Event_SIGABRT, SIGABRT, io_sighook, NULL);
        signal_add(&Event_SIGABRT, NULL);
        signal_set(&Event_SIGINT, SIGINT, io_sighook, NULL);
        signal_add(&Event_SIGINT, NULL);
        signal_set(&Event_SIGQUIT, SIGQUIT, io_sighook, NULL);
        signal_add(&Event_SIGQUIT, NULL);
        signal_set(&Event_SIGTERM, SIGTERM, io_sighook, NULL);
        signal_add(&Event_SIGTERM, NULL);
        assert(Event_STDIN == NULL);
        Event_STDIN = bufferevent_new(0, io_stdio_read, NULL,
                io_stdio_error, NULL);
        if (Event_STDIN == NULL)
                err(1, "bufferevent_new");
        bufferevent_enable(Event_STDIN, EV_READ);

        cgl_init(w, h, s);

        timespecclear(&Win_Hz.m);
        Win_Hz.m.tv_nsec = rhythm;
        if (!timespecisvalid(&Win_Hz.m))
                errx(1, "Win_Hz.m");
        TIMESPEC_TO_TIMEVAL(&Win_Hz.n, &Win_Hz.m);
        evtimer_set(&Win_Clock, tock_turtle, NULL);
        evtimer_add(&Win_Clock, &Win_Hz.n);
}

@ @c
static void
io_sighook (int    sig    unused,
            short  events,
            void  *arg)
{
        assert(events & EV_SIGNAL);
        assert(arg == NULL);

        io_stop();
        printf("\n");
        exit(1);
}

@ @c
static void
io_stdio_error (struct bufferevent *ebuf,
                short               what,
                void               *arg  unused)
{
        assert(ebuf == Event_STDIN);
        if (!(what & EVBUFFER_EOF))
                err(1, "io_stdio_error");
}

@ @c
static void
io_stdio_read (struct bufferevent *ebuf unused,
               void               *arg  unused)
{
        return;
}

@ Called to remove background (signal-handling) events to stop the event loop.

@c
void
io_stop (void)
{
        glfwSetWindowShouldClose(Win, GLFW_TRUE);
        signal_del(&Event_SIGABRT);
        signal_del(&Event_SIGINT);
        signal_del(&Event_SIGQUIT);
        signal_del(&Event_SIGTERM);
        bufferevent_disable(Event_STDIN, EV_READ);
        bufferevent_free(Event_STDIN);
        Event_STDIN = NULL;
}

@ Must not happen until the evnt loop has ended.

@c
void
io_terminate (void)
{
        glfwTerminate();
}

@ TODO: Work out whether |vhz_screen| should be reduced.

@.TODO@>
@c
void
io_reset_clock (struct timespec *frame_start unused)
{
        assert(Win != NULL);
        if (!glfwWindowShouldClose(Win))
                evtimer_add(&Win_Clock, &Win_Hz.n);
}

@ @c
void
io_events (void)
{
        glfwPollEvents();
}

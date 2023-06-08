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
struct event Event_SIGCHLD, Event_Child_Read;
struct bufferevent *Event_Child_Write = NULL;

@ @<IO fun...@>=
void io_events (void);
void io_init (int, int, int, long);
void io_reset_clock (struct timespec *);
void io_stop (void);
void io_terminate (void);
void io_child_handler (int, void (*)(int, short, void *),
        void (*)(int, short, void *));
int io_child_write (char *, size_t);

@ @<IO private...@>=
static void io_child_error (struct bufferevent *, short, void *);
static void io_sighook (int, short, void *);

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
io_child_error (struct bufferevent *ebuf,
                short               what,
                void               *arg  unused)
{
        assert(ebuf == Event_Child_Write);
        if (!(what & EVBUFFER_EOF))
                err(1, "io_child_error");
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
        if (signal_initialized(&Event_SIGCHLD))
                signal_del(&Event_SIGCHLD);
        if (event_initialized(&Event_Child_Read))
                event_del(&Event_Child_Read);
        if (Event_Child_Write) {
                bufferevent_disable(Event_Child_Write, EV_READ);
                bufferevent_free(Event_Child_Write);
                Event_Child_Write = NULL;
        }
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

@ @c
void
io_child_handler (int    cfd,
                  void (*scb)(int, short, void *),
                  void (*rcb)(int, short, void *))
{
        assert(!signal_initialized(&Event_SIGCHLD));
        signal_set(&Event_SIGCHLD, SIGCHLD, scb, NULL);
        signal_add(&Event_SIGCHLD, NULL);
        event_set(&Event_Child_Read, cfd, EV_READ | EV_PERSIST, rcb, NULL);
        event_add(&Event_Child_Read, NULL);
        assert(Event_Child_Write == NULL);
        Event_Child_Write = bufferevent_new(0, NULL, NULL,
                io_child_error, NULL);
        if (Event_Child_Write == NULL)
                err(1, "bufferevent_new");
        bufferevent_enable(Event_Child_Write, EV_WRITE);
}

@ @c
int
io_child_write (char   *buf,
                size_t  len)
{
        return bufferevent_write(Event_Child_Write, buf, len);
}

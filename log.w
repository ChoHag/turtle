@i types.w

@** User Interface.

@c
#include <assert.h>
#include <stdio.h>
@#
#include <event.h>
#include <imsg.h>
@#
#include "turtle.h"
#include "log.h"
@#

@ @(log.h@>=
#ifndef TRTLOG_H
#define TRTLOG_H
void bug (const char *, ...) __attribute__((format(printf, 1, 2)));
void vbug (const char *, va_list);
void inform (const char *, ...) __attribute__((format(printf, 1, 2)));
void vinform (const char *, va_list);
void complain (const char *, ...) __attribute__((format(printf, 1, 2)));
void vcomplain (const char *, va_list);
#endif /* |TRTLOG_H| */

@ @c
void
bug (const char *msg, ...)
{
        if (!Debug)
                return;
        va_list vl;
        va_start(vl, msg);
        vbug(msg, vl);
        va_end(vl);
}

void
vbug (const char *msg,
      va_list     vl)
{
        if (!Debug)
                return;
        vfprintf(stdout, msg, vl);
        fprintf(stdout, "\n");
}

@ @c
void
inform (const char *msg, ...)
{
        if (!Verbose)
                return;
        va_list vl;
        va_start(vl, msg);
        vinform(msg, vl);
        va_end(vl);
}

void
vinform (const char *msg,
         va_list     vl)
{
        if (!Verbose)
                return;
        vfprintf(stdout, msg, vl);
        fprintf(stdout, "\n");
}


@ @c
void
complain (const char *msg, ...)
{
        va_list vl;
        va_start(vl, msg);
        vcomplain(msg, vl);
        va_end(vl);
}

void
vcomplain (const char *msg,
           va_list     vl)
{
        vfprintf(stderr, msg, vl);
        fprintf(stderr, "\n");
}

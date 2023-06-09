@i types.w

@** Sucky Terminal. Mostly \.{st.c} with names changed.

@ @c
#include <assert.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
@#
#include <matrix.h>
#include "cgl-opengl.h"
@#
#include "turtle.h"
#include "cgl.h"
#include "term.h"
#include "newwin.h"
@#
@<Terminal global variables@>@;

@ @(term.h@>=
#ifndef TRTERM_H
#define TRTERM_H
#include <stdbool.h>
#include <stdint.h>
@<Terminal public function declarations@>@;
#endif /* |TRTERM_H| */

@ @<Terminal global...@>=
int Line_FD = -1;

@ @<Terminal public function declarations@>=
bvec3_t rgbatobv3 (uint32_t);
void term_draw (void);
void term_draw_imp (int, int);
void term_init (int, int);
void term_read (int, short, void *);

@ In addition to a bunch of stuff done by |xinit| that GL doesn't
need or does differently st's |main| calls |xsetenv| to set the
\.{WINDOW} environment variable.

|run| then waits for the window to be mapped before forking a child
process for the shell, resizing things at a different layer (``c'')
the reading from the child processes FD for ever.

We just need to fork.

Don't need to worry about buffering to |iofd|, only |cmdfd|.

@c
void
term_init (int col,
           int row)
{
        assert(Line_FD == -1);
        gtnew(row, col);
        gselinit();
        Line_FD = ttynew(NULL, "/bin/sh", NULL, NULL); /* Returns the master side of a pty or an fd to the path in the line cli argument. */
        /* Now |iofd| is the fd to the path in the out cli argument or this processes stdout, |cmdfd| is |Line_FD|. */
        io_child_handler(Line_FD, gsigchld, term_read);

        /* Also all the parts from |xinit| and pals which are skipped. */
        // xloadfonts
        // xloadcols
        /* adjust fixed window geometry */
        // events and a bunch of stuff with the root window
        // Finish off the drawing context
        // xim
        // Mouse pointer?
        // Window manager
        // resettitle
        // xhints
        // selection
}

@ Needs replacement within st.c:

ttyread calls read(cmdfd); called by |ttywriteraw| and |run|.

tprinter calls xwrite(iofd); write a copy of the terminal display
to |iofd|, if it's set. Ultimately called from quite a few places
but just debugging?

ttywriteraw calls pselect and write(cmdfd).

@c
void
term_read (int    fd,
           short  events unused,
           void  *arg    unused)
{
        assert(fd == Line_FD);
        gttyread();
}

@ @c
bvec3_t
rgbatobv3 (uint32_t col)
{
        bvec3_t r;

        r.x = (col & 0xff000000l) >> 24;
        r.y = (col & 0x00ff0000l) >> 16;
        r.z = (col & 0x0000ff00l) >> 8;

        return r;
}

@ The row of the cell is calculated as |lines - y - 1| to invert
the terminals cells' origin at the top left co-ordinates to graphical
origin at the bottom left co-ordinates.

@c
void
term_draw (void)
{
        gtdraw(term_draw_imp);
}

@ @c
#if 0
{{{ Previously:
	drawregion(0, 0, term.col, term.row);
	xdrawcursor(cx, term.c.y, term.line[term.c.y][cx],
			term.ocx, term.ocy, term.line[term.ocy][term.ocx]);
}}}
#endif

void
term_draw_imp (int lines,
               int width)
{
        int x, y;
        Glyph p, r, z = {0};

        if (1) { /* dirty */
                cgl_clear_vertex_buffer();
                for (y = 0; y < lines; y++) {
                        p = z;
                        for (x = 0; x < width; x++) {
                                r = gtruneat(y, x);
                                cgl_draw_glyph(x, lines - y - 1,
                                        rgbatobv3(r.bg), rgbatobv3(r.fg),
                                        FACE_NORMAL, p.u, r.u);
                                if (r.u == ' ') /* Or other unprintable */
                                        p = z;
                                else
                                        p = r;
                        }
                }
        }

        cgl_blit();
}

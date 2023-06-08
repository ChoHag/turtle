@i types.w

@** Graphics linkage.

@c
#include <assert.h>
#include <wchar.h>
@#
#include "newwin.h"
#include "st.h"
#include "win.h"
@#
#include "cgl-opengl.h"
#include "cgl.h"

@<Very global variables@>@;

@ To replace \.{win.h} eventually.

@(newwin.h@>=
#ifndef TURTLE_NEWWIN_H
#define TURTLE_NEWWIN_H
#include <stdint.h>
@<Shared type definitions@>@;
@<Shared bridging functions@>@;
#endif /* |TURTLE_NEWWIN_H| */

@ We start with terribly-named global variables
that stand in for doing any of the hard parts of an interactive
program.

What program is execed by st depends of these precedence rules:

1: program passed with -e

2: scroll and/or utmp

3: SHELL environment variable

4: value of shell in /etc/passwd

5: value of shell in config.h

2 and 5 are stupid.

Also ignore |utmp| and |scroll|; these exist in support of poorly
thought out ideas the suckless developers have wrapped their egos
around and can't let go of.

@<Very global...@>=
char *shell = "/bin/sh";
char *utmp = NULL;
char *scroll = NULL; /* scroll program: just don't. */
char *stty_args = "stty raw pass8 nl -echo -iexten -cstopb 38400";

@ Default \.{TERM} value.

@<Very global...@>=
char *termname = "st-256color";

@ Terminal colours. There are 256 of which the first 16 are used
in escape sequences. Colours 256--259 are additionally defined for
internal use.

@<Very global...@>=
const char *colorname[] = {
	/* 8 normal colors */
	"black",
	"red3",
	"green3",
	"yellow3",
	"blue2",
	"magenta3",
	"cyan3",
	"gray90",

	/* 8 bright colors */
	"gray50",
	"red",
	"green",
	"yellow",
	"#5c5cff",
	"magenta",
	"cyan",
	"white",

	[255] = 0,

	/* more colors can be added after 255 to use with DefaultXX */
	"#cccccc",
	"#555555",
	"gray90", /* default foreground colour */
	"black", /* default background colour */
};

@ Default colors (index into |colorname|). Foreground, background,
cursor, reverse cursor.

@<Very global...@>=
unsigned int defaultfg = 258;
unsigned int defaultbg = 259;
unsigned int defaultcs = 256;
unsigned int defaultrcs = 257;

@ @<Very global...@>=
wchar_t *worddelimiters = L" "; /* More advanced example: |L" `'\"()[]{}"| */

@ Changing the terminal's tab widths from the opinionated,
convention-bucking 8 spaces is essential and the ideal way to do
it is (you couldn't make this up) to {\it compile your own emulator\/},
akin to how the owners of real terminals would wire a whole new
circuit board from scratch whenever they wanted to change the
screen's brightness.

Just to be safe it's an unsigned int, in case we need to support
tab widths up to 4 billion.

@<Very global...@>=
unsigned int tabspaces = 8;

@ ``[I]dentification sequence returned in DA and DECID''.

@<Very global...@>=
char *vtiden = "\033[?6c";

@ This feature needs to be optional because its almost entirely
incomplete apart from what's necessary to get vi to work. But the
problem is the systems, not the developers who can't be arsed to
use them properly.

@<Very global...@>=
int allowaltscreen = 1;

@ Core data types copied from \.{st.h}.

@<Shared type...@>=
typedef uint_least32_t Rune;

#define Glyph Glyph_   /* No explanation for this. */
typedef struct {
	Rune     u;    /* character code */
	uint16_t mode; /* attribute flags */
	uint32_t fg;   /* foreground */
	uint32_t bg;   /* background */
} Glyph;


@ @<Shared bridg...@>=
void gxbell (void);
void gxclipcopy (void);
int gxgetcolor (int, unsigned char *, unsigned char *, unsigned char *);
void gxloadcols (void);
int gxsetcolorname (int, const char *);
int gxsetcursor (int);
void gxsetpointermotion (int);
void gxsetsel (char *);
void gxsettitle (char *);


@ |xsettitle| was called from \.{st.c} to set the title of the
terminal emulator's window.

@c
void
gxsettitle (char *str)
{
#ifdef TURTLE_USEGL
        cgl_set_title(str);
#else
        xsettitle(str);
#endif
}

@ An icon title in X is a string. The manual page for |XSetIconName|
and its peers, which |xseticontitle| eventually calls is perhaps
the best example of 100\% useless documentation that I have ever
seen. It goes to great lenghts to explain the obvious --- what the
\.{display} or \.{window} variables mean when communication with
an X display about a window's properties, or what functions with
\.{Get} or \.{Set} in their name do --- but doesn't explain the
significance of the \.{WM} in half of the functions or why they
take an \.{XTextProperty} instead of a null-terminated string, or
even obliquely refer to the fact that an icon is really a picture
and not a string of text.

It takes the effort to inform you that memory allocation or bad
input errors can occur (who knew?!), but doesn't acknowledge that
it only lists them for half of the functions or explain why.

After the function declarations the page could read simply ``these
functions do what their names describe''. In fact that's pretty
much what it does do, but using a {\it lot\/} more words.

But I'm sure a box was ticked somewhere to say that those four
functions are ``documented''.

In the name of portability, GLFW does something entirely different
from everything it's portable between.

@c
void
gxseticontitle (char *str)
{
#ifdef TURTLE_USEGL
        assert(str || !str);
        return; /* Not implemented */
#else
        xseticontitle(str);
#endif
}

@ @c
void
gxbell (void)
{
#ifdef TURTLE_USEGL
        return; /* Not implemented */
#else
        xbell();
#endif
}

@ @c
int
gxsetcursor (int c)
{
#ifdef TURTLE_USEGL
        assert(c || !c);
        return 0; /* Not implemented */
#else
        return xsetcursor(c);
#endif
}

@ |xsetmode| has nothing to do with X but the bits it flips are
defined in the structure that holds other data associated with the
X server window. The GL structure currently has no such bits.

@c
void
gxsetmode (int          set,
           unsigned int flags)
{
#ifdef TURTLE_USEGL
        assert(set || !set);
        assert(flags || !flags);
        return; /* Not implemented */
#else
        xsetmode(set, flags);
#endif
}

@ @c
void
gxsetpointermotion (int set)
{
#ifdef TURTLE_USEGL
        assert(set || !set);
        return; /* Not implemented */
#else
        xsetpointermotion(set);
#endif
}





@ Resets the definition of the 256 available colours. In X this is
concerned with allocating colour objects in the X server. For now
GL doesn't support colours.

@c
void
gxloadcols (void)
{
#ifdef TURTLE_USEGL
        return; /* Not implemented */
#else
        xloadcols();
#endif
}

int
gxsetcolorname (int         x,
                const char *name)
{
#ifdef TURTLE_USEGL
        assert(x || !x);
        assert(name || !name);
        return 0; /* Not implemented */
#else
        return xsetcolorname(x, name);
#endif
}

int
gxgetcolor (int            x,
            unsigned char *r,
            unsigned char *g,
            unsigned char *b)
{
#ifdef TURTLE_USEGL
        assert(x || r || g || b || 1);
        return 0; /* Not implemented */
#else
        return xgetcolor(x, r, g, b);
#endif
}

@ ``[A]llow certain non-interactive (insecure) window operations
such as: setting the clipboard text''. In fact that's the only
operation associated with this flag and it's ``insecure'' because
an application that requests to read from or write to the clipboard
can ... read from and write to the clipboard?

@<Very global...@>=
int allowwindowops = 0;

@ Turtle will likely use the same X selection mechanism once I
figure out how to get the display and window handles from GLFW.

@c
void
gxclipcopy (void)
{
#ifdef TURTLE_USEGL
        return; /* Not implemented */
#else
        xclipcopy();
#endif
}

void
gxsetsel (char *str)
{
#ifdef TURTLE_USEGL
        assert(str || !str);
        return; /* Not implemented */
#else
        xsetsel(str);
#endif
}

@* Exposing functions from \.{st.c}.

@<Shared bridg...@>=
void gselnew (void);
void gtnew (int, int);
void gtresize (int, int);
Glyph gtruneat (int, int);

@ @c
void
gtnew (int col,
       int row)
{
        tnew(col, row);
}

@ @c
void
gtresize (int col,
          int row)
{
        tresize(col, row);
}

@ @c
void
gtdraw (void (*imp)(int, int))
{
        tdraw(imp);
}

@ @c
Glyph
gtruneat (int y,
          int x)
{
        return truneat(y, x);
}

@ @c
void
gselinit (void)
{
        selinit();
}

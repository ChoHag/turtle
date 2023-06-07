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
#include "term.h"
#include "cgl.h"
@#
@<Terminal global variables@>@;
@<Terminal private function declarations@>@;

@ @(term.h@>=
#ifndef TRTERM_H
#define TRTERM_H
#include <stdbool.h>
#include <stdint.h>
@h
@<Terminal type definitions@>@;
@<Terminal exported variables@>@;
@<Terminal public function declarations@>@;
#endif /* |TRTERM_H| */

@ @d ISDELIM(u)		(u && wcschr(worddelimiters, u))
@<Terminal type...@>=
typedef uint_least32_t trt_rune;

@ @<Terminal type...@>=
typedef struct {
	trt_rune u;    /* Uni-code point */
	short    mode; /* Attribute flags */
	bvec3_t  fg;   /* foreground  */
	bvec3_t  bg;   /* background  */
} trt_cell;

enum glyph_attribute {
	ATTR_NULL       = 0,
	ATTR_BOLD       = 1 << 0,
	ATTR_FAINT      = 1 << 1,
	ATTR_ITALIC     = 1 << 2,
	ATTR_UNDERLINE  = 1 << 3,
	ATTR_BLINK      = 1 << 4,
	ATTR_REVERSE    = 1 << 5,
	ATTR_INVISIBLE  = 1 << 6,
	ATTR_STRUCK     = 1 << 7,
	ATTR_WRAP       = 1 << 8,
	ATTR_WIDE       = 1 << 9,
	ATTR_WDUMMY     = 1 << 10,
	ATTR_BOLD_FAINT = ATTR_BOLD | ATTR_FAINT,
};

@ @<Terminal type...@>=
typedef struct {
	trt_cell attr; /* current char attributes */
	int x;
	int y;
	char state;
} trt_cursor;

enum cursor_movement {
	CURSOR_SAVE,
	CURSOR_LOAD
};

enum cursor_state {
	CURSOR_DEFAULT  = 0,
	CURSOR_WRAPNEXT = 1,
	CURSOR_ORIGIN   = 2
};

@ @d FLAG_SET(flag) ((Table.mode & (flag)) != 0)
@<Terminal type...@>=
typedef struct {
	int row;          /* nb row */
	int col;          /* nb col */
	trt_cell **line;  /* screen */
	trt_cell **alt;   /* alternate screen */
	int *dirty;       /* dirtyness of lines */
	trt_cursor c;     /* cursor */
        trt_cursor oc;    /* Old (?) cursor */
	int top;          /* top    scroll limit */
	int bot;          /* bottom scroll limit */
	int mode;         /* terminal mode flags */
	int esc;          /* escape state flags */
	char trantbl[4];  /* charset table translation */
	int charset;      /* current charset */
	int icharset;     /* selected charset for sequence */
	int *tabs;
	trt_rune lastc;   /* last printed char outside of sequence, 0 if control */
} trt_table;

enum term_mode {
	MODE_WRAP        = 1 << 0,
	MODE_INSERT      = 1 << 1,
	MODE_ALTSCREEN   = 1 << 2,
	MODE_CRLF        = 1 << 3,
	MODE_ECHO        = 1 << 4,
	MODE_PRINT       = 1 << 5,
	MODE_UTF8        = 1 << 6,
};

enum charset {
	CS_GRAPHIC0,
	CS_GRAPHIC1,
	CS_UK,
	CS_USA,
	CS_MULTI,
	CS_GER,
	CS_FIN
};

@ @<Terminal global...@>=
char *stty_args = "stty raw pass8 nl -echo -iexten -cstopb 38400";
wchar_t *worddelimiters = L" "; /* More advanced example: |L" `'\"()[]{}"| */
trt_table Table = {0};

@ @<Terminal exported variables@>=
extern char *stty_args;
extern wchar_t *worddelimiters;
extern trt_table Table;

@ @<Terminal public function declarations@>=
void term_draw (void);
void term_init (int, int);
void term_resize (int, int);

@ @<Terminal private function declarations@>=
static void term_clear_region (int, int, int, int);
static void term_reset (void);
static void term_set_dirty (int, int);
@#
static void term_swap_alt (void);
@#
static void term_scroll_down (int, int);
static void term_scroll_selection (int, int);
static void term_scroll_up (int, int);
static void term_set_scroll (int, int);
@#
static void sel_clear (void);
static bool sel_is (int, int);
static void sel_normal (void);
static void sel_snap(int *, int *, int);
@#
static void term_cursor (int);
static void term_moveato (int, int);
static void term_moveto (int, int);
@#
bvec3_t parse_colour (char *);

@ @c
void
term_init (int col,
           int row)
{
        assert(Table.row == 0 && Table.col == 0);
        term_resize(col, row);
        term_reset();
}

@ @d TABWIDTH 8
@c
void
term_reset (void)
{
	size_t i;

	Table.c = (trt_cursor){{
		.mode = ATTR_NULL,
		.fg   = parse_colour(RGB_Name[RGB_DEFAULT_FG]),
		.bg   = parse_colour(RGB_Name[RGB_DEFAULT_BG])
	}, .x = 0, .y = 0, .state = CURSOR_DEFAULT};

	memset(Table.tabs, 0, Table.col * sizeof(*Table.tabs));
	for (i = TABWIDTH; i < (size_t) Table.col; i += TABWIDTH)
		Table.tabs[i] = 1;
	Table.top = 0;
	Table.bot = Table.row - 1;
	Table.mode = MODE_WRAP|MODE_UTF8;
	memset(Table.trantbl, CS_USA, sizeof(Table.trantbl));
	Table.charset = 0;

	for (i = 0; i < 2; i++) {
		term_moveto(0, 0);
		term_cursor(CURSOR_SAVE);
		term_clear_region(0, 0, Table.col-1, Table.row-1);
		term_swap_alt();
	}
}

@ @c
void
term_resize (int col,
             int row)
{
	int i;
	int minrow = MIN(row, Table.row);
	int mincol = MIN(col, Table.col);
	int *bp;
	trt_cursor c;

	if (col < 1 || row < 1) {
		fprintf(stderr,
		        "tresize: error resizing to %dx%d\n", col, row);
		return;
	}

	/*
	 * slide screen to keep cursor where we expect it -
	 * tscrollup would work here, but we can optimize to
	 * memmove because we're freeing the earlier lines
	 */
	for (i = 0; i <= Table.c.y - row; i++) {
		free(Table.line[i]);
		free(Table.alt[i]);
	}
	/* ensure that both src and dst are not NULL */
	if (i > 0) {
		memmove(Table.line, Table.line + i, row * sizeof(trt_cell *));
		memmove(Table.alt, Table.alt + i, row * sizeof(trt_cell *));
	}
	for (i += row; i < Table.row; i++) {
		free(Table.line[i]);
		free(Table.alt[i]);
	}

	/* resize to new height */
	Table.line  = realloc(Table.line,  row * sizeof(*Table.line));
	Table.alt   = realloc(Table.alt,   row * sizeof(*Table.line));
	Table.dirty = realloc(Table.dirty, row * sizeof(*Table.dirty));
	Table.tabs  = realloc(Table.tabs,  col * sizeof(*Table.tabs));

	/* resize each row to new width, zero-pad if needed */
	for (i = 0; i < minrow; i++) {
		Table.line[i] = realloc(Table.line[i], col * sizeof(trt_cell));
		Table.alt[i]  = realloc(Table.alt[i],  col * sizeof(trt_cell));
	}

	/* allocate any new rows */
	for (/* |i = minrow| */; i < row; i++) {
		Table.line[i] = malloc(col * sizeof(trt_cell));
		Table.alt[i]  = malloc(col * sizeof(trt_cell));
	}
	if (col > Table.col) {
		bp = Table.tabs + Table.col;

		memset(bp, 0, sizeof(*Table.tabs) * (col - Table.col));
		while (--bp > Table.tabs && !*bp)
			/* nothing */ ;
		for (bp += TABWIDTH; bp < Table.tabs + col; bp += TABWIDTH)
			*bp = 1;
	}
	/* update terminal size */
	Table.col = col;
	Table.row = row;
	/* reset scrolling region */
	term_set_scroll(0, row-1);
	/* make use of the LIMIT in tmoveto */
	term_moveto(Table.c.x, Table.c.y);
	/* Clearing both screens (it makes dirty all lines) */
	c = Table.c;
	for (i = 0; i < 2; i++) {
		if (mincol < col && 0 < minrow) {
			term_clear_region(mincol, 0, col - 1, minrow - 1);
		}
		if (0 < col && minrow < row) {
			term_clear_region(0, minrow, col - 1, row - 1);
		}
		term_swap_alt();
		term_cursor(CURSOR_LOAD);
	}
	Table.c = c;
}

@ The row of the cell is calculated as |Table.row - y - 1| to invert
the terminals cells' origin at the top left co-ordinates to graphical
origin at the bottom left co-ordinates.

@c
void
term_draw (void)
{
        trt_cell p, r, z = {0};
        trt_cursor mc;
        int x, y;

        assert(Table.row && Table.col);
        /* Ensure the old cursor (only?) is within range */
        LIMIT(Table.oc.x, 0, Table.col - 1);
        LIMIT(Table.oc.y, 0, Table.row - 1);
        mc = Table.c;
        if (Table.line[Table.oc.y][Table.oc.x].mode & ATTR_WDUMMY)
                Table.oc.x--;
        if (Table.line[mc.y][mc.x].mode & ATTR_WDUMMY)
                mc.x--;

        if (1) { /* dirty */
                cgl_clear_vertex_buffer();
                for (y = 0; y < Table.row; y++) {
                        p = z;
                        for (x = 0; x < Table.col; x++) {
                                r = Table.line[y][x];
                                cgl_draw_glyph(x, Table.row - y - 1, r.bg, r.fg,
                                        FACE_NORMAL, p.u, y+x);//r.u);
                                if (r.u == ' ') /* Or other unprintable */
                                        p = z;
                                else
                                        p = r;
                        }
                }
        }

        cgl_blit();
#if 0
        for (y = 0; y < Table.row; y++) {
                cgl_draw_line(Table.line[y], y, 0, Table.col);
        }
        cgl_draw_cursor(mc, Table.line[mc.y][mc.x],
                Table.oc, Table.line[Table.oc.y][Table.oc.x]);
        cgl_draw_end();
        if (Table.oc.x != mc.x || Table.oc.y != mc.y)
                xximspot(mc);
#endif
        Table.oc = mc;
}

@ @c
void
term_clear_region (int x1,
                   int y1,
                   int x2,
                   int y2)
{
	int x, y, temp;
	trt_cell *gp;

	if (x1 > x2)
		temp = x1, x1 = x2, x2 = temp;
	if (y1 > y2)
		temp = y1, y1 = y2, y2 = temp;

	LIMIT(x1, 0, Table.col-1);
	LIMIT(x2, 0, Table.col-1);
	LIMIT(y1, 0, Table.row-1);
	LIMIT(y2, 0, Table.row-1);

	for (y = y1; y <= y2; y++) {
		Table.dirty[y] = 1;
		for (x = x1; x <= x2; x++) {
			gp = &Table.line[y][x];
			if (sel_is(x, y))
				sel_clear();
			gp->fg = Table.c.attr.fg;
			gp->bg = Table.c.attr.bg;
			gp->mode = 0;
			gp->u = ' ';
		}
	}
}

@ @d term_full_dirty() term_set_dirty(0, Table.row - 1)
@c
void
term_set_dirty (int top,
                int bot)
{
	int i;

	LIMIT(top, 0, Table.row-1);
	LIMIT(bot, 0, Table.row-1);

	for (i = top; i <= bot; i++)
		Table.dirty[i] = 1;
}


@* Alternate screen.

@c
void
term_swap_alt (void)
{
	trt_cell **tmp = Table.line;

	Table.line = Table.alt;
	Table.alt = tmp;
	Table.mode ^= MODE_ALTSCREEN;
	term_full_dirty();
}

@* Scrolling.

@c
void
term_scroll_down (int orig,
                  int n)
{
	int i;
	trt_cell *temp;

	LIMIT(n, 0, Table.bot-orig+1);

	term_set_dirty(orig, Table.bot-n);
	term_clear_region(0, Table.bot-n+1, Table.col-1, Table.bot);

	for (i = Table.bot; i >= orig+n; i--) {
		temp = Table.line[i];
		Table.line[i] = Table.line[i-n];
		Table.line[i-n] = temp;
	}

	term_scroll_selection(orig, n);
}

@ @c
void
term_scroll_up (int orig,
                int n)
{
	int i;
	trt_cell *temp;

	LIMIT(n, 0, Table.bot-orig+1);

	term_clear_region(0, orig, Table.col-1, orig+n-1);
	term_set_dirty(orig+n, Table.bot);

	for (i = orig; i <= Table.bot-n; i++) {
		temp = Table.line[i];
		Table.line[i] = Table.line[i+n];
		Table.line[i+n] = temp;
	}

	term_scroll_selection(orig, -n);
}

@ @c
void
term_scroll_selection (int orig,
                       int n)
{
	if (Selection.ob.x == -1)
		return;

	if (BETWEEN(Selection.nb.y, orig, Table.bot) != BETWEEN(Selection.ne.y, orig, Table.bot)) {
		sel_clear();
	} else if (BETWEEN(Selection.nb.y, orig, Table.bot)) {
		Selection.ob.y += n;
		Selection.oe.y += n;
		if (Selection.ob.y < Table.top || Selection.ob.y > Table.bot ||
		    Selection.oe.y < Table.top || Selection.oe.y > Table.bot) {
			sel_clear();
		} else {
			sel_normal();
		}
	}
}

@ @c
void
term_set_scroll (int t,
                 int b)
{
	int temp;

	LIMIT(t, 0, Table.row-1);
	LIMIT(b, 0, Table.row-1);
	if (t > b) {
		temp = t;
		t = b;
		b = temp;
	}
	Table.top = t;
	Table.bot = b;
}

@* Selection.

@ @<Terminal type...@>=
typedef struct {
	int mode;
	int type;
	int snap;
	/*
	 * Selection variables:
	 * nb – normalized coordinates of the beginning of the selection
	 * ne – normalized coordinates of the end of the selection
	 * ob – original coordinates of the beginning of the selection
	 * oe – original coordinates of the end of the selection
	 */
	struct {
		int x, y;
	} nb, ne, ob, oe;

	int alt;
} trt_select;

enum selection_mode {
	SEL_IDLE  = 0,
	SEL_EMPTY = 1,
	SEL_READY = 2
};

enum selection_type {
	SEL_REGULAR     = 1,
	SEL_RECTANGULAR = 2
};

enum selection_snap {
	SNAP_WORD = 1,
	SNAP_LINE = 2
};

@ @<Terminal global...@>=
trt_select Selection;

@ @c
int
term_linelen(int y)
{
	int i = Table.col;

	if (Table.line[y][i - 1].mode & ATTR_WRAP)
		return i;

	while (i > 0 && Table.line[y][i - 1].u == ' ')
		--i;

	return i;
}

@ @c
bool
sel_is (int x,
        int y)
{
	if (Selection.mode == SEL_EMPTY || Selection.ob.x == -1 ||
			Selection.alt != FLAG_SET(MODE_ALTSCREEN))
		return false;

	if (Selection.type == SEL_RECTANGULAR)
		return BETWEEN(y, Selection.nb.y, Selection.ne.y)
		    && BETWEEN(x, Selection.nb.x, Selection.ne.x);

	return BETWEEN(y, Selection.nb.y, Selection.ne.y)
	    && (y != Selection.nb.y || x >= Selection.nb.x)
	    && (y != Selection.ne.y || x <= Selection.ne.x);
}

@ @c
void
sel_clear (void)
{
	if (Selection.ob.x == -1)
		return;
	Selection.mode = SEL_IDLE;
	Selection.ob.x = -1;
	term_set_dirty(Selection.nb.y, Selection.ne.y);
}

@ @c
void
sel_normal (void)
{
	int i;

	if (Selection.type == SEL_REGULAR && Selection.ob.y != Selection.oe.y) {
		Selection.nb.x = Selection.ob.y < Selection.oe.y ? Selection.ob.x : Selection.oe.x;
		Selection.ne.x = Selection.ob.y < Selection.oe.y ? Selection.oe.x : Selection.ob.x;
	} else {
		Selection.nb.x = MIN(Selection.ob.x, Selection.oe.x);
		Selection.ne.x = MAX(Selection.ob.x, Selection.oe.x);
	}
	Selection.nb.y = MIN(Selection.ob.y, Selection.oe.y);
	Selection.ne.y = MAX(Selection.ob.y, Selection.oe.y);

	sel_snap(&Selection.nb.x, &Selection.nb.y, -1);
	sel_snap(&Selection.ne.x, &Selection.ne.y, +1);

	/* expand selection over line breaks */
	if (Selection.type == SEL_RECTANGULAR)
		return;
	i = term_linelen(Selection.nb.y);
	if (i < Selection.nb.x)
		Selection.nb.x = i;
	if (term_linelen(Selection.ne.y) <= Selection.ne.x)
		Selection.ne.x = Table.col - 1;
}

void
sel_snap (int *x,
          int *y,
          int  direction)
{
	int newx, newy, xt, yt;
	int delim, prevdelim;
	const trt_cell *gp, *prevgp;

	switch (Selection.snap) {
	case SNAP_WORD:
		/*
		 * Snap around if the word wraps around at the end or
		 * beginning of a line.
		 */
		prevgp = &Table.line[*y][*x];
		prevdelim = ISDELIM(prevgp->u);
		for (;;) {
			newx = *x + direction;
			newy = *y;
			if (!BETWEEN(newx, 0, Table.col - 1)) {
				newy += direction;
				newx = (newx + Table.col) % Table.col;
				if (!BETWEEN(newy, 0, Table.row - 1))
					break;

				if (direction > 0)
					yt = *y, xt = *x;
				else
					yt = newy, xt = newx;
				if (!(Table.line[yt][xt].mode & ATTR_WRAP))
					break;
			}

			if (newx >= term_linelen(newy))
				break;

			gp = &Table.line[newy][newx];
			delim = ISDELIM(gp->u);
			if (!(gp->mode & ATTR_WDUMMY) && (delim != prevdelim
					|| (delim && gp->u != prevgp->u)))
				break;

			*x = newx;
			*y = newy;
			prevgp = gp;
			prevdelim = delim;
		}
		break;
	case SNAP_LINE:
		/*
		 * Snap around if the the previous line or the current one
		 * has set |ATTR_WRAP| at its end. Then the whole next or
		 * previous line will be selected.
		 */
		*x = (direction < 0) ? 0 : Table.col - 1;
		if (direction < 0) {
			for (; *y > 0; *y += direction) {
				if (!(Table.line[*y-1][Table.col-1].mode
						& ATTR_WRAP)) {
					break;
				}
			}
		} else if (direction > 0) {
			for (; *y < Table.row-1; *y += direction) {
				if (!(Table.line[*y][Table.col-1].mode
						& ATTR_WRAP)) {
					break;
				}
			}
		}
		break;
	}
}


@* Cursor.

@c
void
term_cursor (int mode)
{
	static trt_cursor c[2];
	int alt = FLAG_SET(MODE_ALTSCREEN);

	if (mode == CURSOR_SAVE) {
		c[alt] = Table.c;
	} else if (mode == CURSOR_LOAD) {
		Table.c = c[alt];
		term_moveto(c[alt].x, c[alt].y);
	}
}

@ /* for absolute user moves, when decom is set */
@c
void
term_moveato (int x,
              int y)
{
	term_moveto(x, y + ((Table.c.state & CURSOR_ORIGIN) ? Table.top: 0));
}

@ @c
void
term_moveto (int x,
             int y)
{
	int miny, maxy;

	if (Table.c.state & CURSOR_ORIGIN) {
		miny = Table.top;
		maxy = Table.bot;
	} else {
		miny = 0;
		maxy = Table.row - 1;
	}
	Table.c.state &= ~CURSOR_WRAPNEXT;
	Table.c.x = LIMIT(x, 0, Table.col-1);
	Table.c.y = LIMIT(y, miny, maxy);
}

@* Colour.

@d RGB_DEFAULT_CS  256
@d RGB_DEFAULT_RCS 257
@d RGB_DEFAULT_FG  258
@d RGB_DEFAULT_BG  259
@<Terminal global...@>=
char *RGB_Name[] = {
	/* normal */
	"black",
	"red3",
	"green3",
	"yellow3",
	"blue2",
	"magenta3",
	"cyan3",
	"gray90",

	/* bright */
	"gray50",
	"red",
	"green",
	"yellow",
	"#5c5cff",
	"magenta",
	"cyan",
	"white",

	[255] = NULL,

	/* internal use */
	"#cccccc",
	"#555555",
	"#e6e6e6",
	"#000000",
};

@ TODO: We have an X connection somewhere --- use it to decode
colour names.

@c
bvec3_t
parse_colour (char *name)
{
        bvec3_t r = {0};
        char *n, v;
        int i;

        if (name[0] && name[0] == '#') {
                n = (char *) &r;
                for (i = 1; i <= 6; i++) {
                        if (!isxdigit(name[i]))
                                return bvec3(0,0,0); // and warn
                        v = isdigit(name[i]) ? name[i] - '0'
                          : name[i] >= 'a' ? name[i] - 'a'
                          : name[i] - 'A';
                        v <<= 4 * (i & 1);
                        n[(i - 1) >> 1] |= v;
                }
                if (name[6])
                        return bvec3(0,0,0); // and warn
        }
        return r;
}

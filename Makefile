CTANGLE?=       ctangle
CWEAVE?=        cweave
PDFTEX?=        pdftex
TEST?=          prove

CFLAGS+=        -D_BSD_SOURCE -D_XOPEN_SOURCE=700 -D_POSIX_C_SOURCE=200809
# CFLAGS+=	-MD -MP
CFLAGS+=        -Wall -Wpedantic -Wextra -Wno-implicit-fallthrough
CFLAGS+=	-DTURTLE_USEGL=1
CFLAGS+=        -I. $$(pkg-config --cflags gl glew glfw3 freetype2)
LDFLAGS+=	-lm -lutil -levent
LDFLAGS+=       $$(pkg-config --libs gl glew glfw3 freetype2)

SHADERS=        fragment.o vertex.o
MODULES=        turtle.o cgl.o io.o log.o matrix.o st.o term.o vector.o win.o
FREETYPE=
FREETYPE+=	ft/distance-field.o
FREETYPE+=	ft/edtaa3func.o
FREETYPE+=	ft/ftgl-utils.o
FREETYPE+=	ft/texture-atlas.o
FREETYPE+=	ft/texture-font.o

### Normal rules

turtle: ${MODULES} ${FREETYPE}
	${LINK.c} ${MODULES} ${FREETYPE} -o turtle

### Dependencies

${MODULES}: matrix.h

${FREETYPE}: matrix.h cgl-opengl.h

cgl-opengl.h: cgl.h
newwin.h: win.c

cgl.o: turtle.h io.h log.h newwin.h term.h vector.h
cgl.o: fragment.c vertex.c
io.o: turtle.h cgl.h log.h term.h
log.o: turtle.h
st.o: st.c st.h win.h cgl.h newwin.h
term.o: turtle.h cgl.h newwin.h
turtle.o: io.h cgl.h log.h term.h
win.o: cgl.h st.h win.h

*.tex: format.w types.w

### Special rules

all: turtle

matrix.o: matrix.h
	# Doesn't treat a file ending in .h as C source...
	ln -sfn matrix.h matrix.c
	${COMPILE.c} -DMATH_3D_IMPLEMENTATION matrix.c -o matrix.o
	rm -f matrix.c

vertex.glsl fragment.glsl: cgl.c

clean:
	rm -f ft/*.o
	rm -f {turtle,cgl,io,log,term}.[cdh] {fragment,vertex}.{[cd],glsl} cgl-opengl.h
	rm -f *.o turtle
	rm -f *.tex *.{idx,log,scn,toc} *.pdf
	rm -f core *.core

### Auto rules

.SUFFIXES: .glsl .pdf .tex .w

.glsl.c:
	name=$$(echo $< | sed 's/.glsl//; s/-/_/g'); \
	bin/bin2c GUARD_$$name Source_$$name $< >$@

.w.c:
	mkdir -p t
	${CTANGLE} ${.IMPSRC}

.w.h:
	mkdir -p t
	${CTANGLE} ${.IMPSRC}

.w.tex:
	${CWEAVE} ${.IMPSRC}

.tex.pdf:
	${PDFTEX} ${.IMPSRC}

# Needs an explicit output filename to build in subdirectories
.c.o:
	${COMPILE.c} ${.IMPSRC} -o ${.TARGET}

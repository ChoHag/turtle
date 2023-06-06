@i types.w

@** GL Canvas.

@c
#include <assert.h>
#include <err.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
@#
#include <matrix.h>
#include <event.h>
#include <imsg.h>
#include "cgl-opengl.h"
#include "ft/texture-atlas.h"
#include "ft/texture-font.h"
@#
#include "turtle.h"
#include "term.h"
#include "cgl.h"
#include "io.h"
#include "log.h"
#include "vector.h"
@#
@<GL global variables@>@;
@<GL private functions@>@;

@ @(cgl.h@>=
#ifndef TRT_CGL_H
#define TRT_CGL_H
#include "ft/markup.h" // lose this
@h
@<GL type definitions@>@;
@<GL shared variables@>@;
@<GL function declarations@>@;
#endif /* |TRT_CGL_H| */

@ Common OpenGL headers.

% The thinspace directives in the include line here confuse the
% weaver's understanding of the <...> token.

@(cgl-opengl.h@>=
#ifndef TRT_OPENGL_H
#define TRT_OPENGL_H
@#
#include <GL/glew.h>
#if defined(_WIN32) || defined(_WIN64)
#@,@,@,@,include <GL/wglew.h>
#endif
@#
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#endif /* |TRT_OPENGL_H| */

@ Terminals can display from multiple fonts. For the time being
there is one, also the special ``normal'' font. The collection of
a particular font and its various metadata is a Face.

@<GL type def...@>=
enum {
        FACE_NORMAL,
        FACE_LENGTH
};

typedef struct {
        markup_t m;
        float width, height, inset;
} cgl_face;

@ OpenGL is concerned with pushing 3D co-ordinates along with other
data associated with them to the rendering engine. The collection
of a 3D co-ordinate and its associated metadata is known as a vertex.

@<GL type def...@>=
typedef struct {
        vec3_t pos;
        vec2_t tex;
        vec3_t col;
} cgl_vertex;

@ The code running on the CPU builds collections of data which it
sends to OpenGL for rendering on the GPU. These are handles to that
data.

@<GL global...@>=
vector_xt *Draw_Buffer, *Draw_Index; /* Application copy of vertices to render. */
cgl_face Face[FACE_LENGTH]; /* Font definitions. */
texture_atlas_t *Glyph_Atlas; /* A texture of renderred glyphs. */
GLuint Shader_Program; /* The programs running on the GPU that calculate co-ordinates and colours. */
GLuint VAO; /* A pointer to a set of OpenGL references. */
GLuint VBO[2]; /* Pointers to an OpenGL copy of the vertex data. */
GLFWwindow *Win; /* The main window. */

@ @<GL shared...@>=
extern GLFWwindow *Win;

@ @<GL fun...@>=
void cgl_blit (void);
void cgl_cb_resize (GLFWwindow *, int, int);
void cgl_events (void);
void cgl_init (int, int, int);
void cgl_window (int, int);
void cgl_clear_vertex_buffer (void);
void cgl_draw_glyph (int, int, bvec3_t, bvec3_t, int, trt_rune, trt_rune);
void cgl_draw_space (int, int, bvec3_t, int);

@ @<GL private...@>=
static void cgl_cb_close (GLFWwindow *);
static void cgl_cb_debug (GLenum, GLenum, unsigned int, GLenum, GLsizei,
        const char *,@| const void *);
static GLuint cgl_compile_shader (GLenum, char *, long);
static void cgl_glerror (int, const char *);
static void cgl_load_shader_program (void);
static void cgl_report_errors (char *);
static cgl_face cgl_load_font (char *, size_t);

@ Many things to do here. Should probably be broken up into sections.

@c
void
cgl_init (int w,
          int h,
          int font_size)
{
        int flags;

        /* Load the font definitions and prepare an atlas of rendered glyphs. */

        Glyph_Atlas = texture_atlas_new(512, 512, 4);
        if (Glyph_Atlas == NULL)
                err(1, "texture_font_get_glyph");
        glGenTextures(1, &Glyph_Atlas->id);
        Face[FACE_NORMAL] = cgl_load_font("VeraMono.ttf", font_size * 3);

        /* Initialise OpenGL and report errors as they're encountered. */

        glfwSetErrorCallback(cgl_glerror);
        if (!glfwInit())
                errx(1, "glfwInit");
        inform("Using GLFW %s", glfwGetVersionString());

        cgl_window(w, h);
        cgl_report_errors("cgl_window");

        /* The extensions must be activated after a window is opened
                because reasons. */

        if (glewInit() != GLEW_OK)
                errx(1, "glewInit"); /* {\it After\/} the window is opened. */
        inform("Using GLEW %s", glewGetString(GLEW_VERSION));

        /* Activate mostly-unused debugging hooks. */

        glGetIntegerv(GL_CONTEXT_FLAGS, &flags);
        if (flags & GL_CONTEXT_FLAG_DEBUG_BIT) {
                glEnable(GL_DEBUG_OUTPUT);
                glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
                glDebugMessageCallback(cgl_cb_debug, NULL);
                glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE,
                        GL_DONT_CARE, 0, NULL, GL_TRUE);
        }

        /* This is mostly of use for 3D rendering --- don't bother
                calculating the backs of things. */

#if 0 /* gl.w */
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        glFrontFace(GL_CW);
#endif

        /* Probably something to do with pixel smoothing. Not
                particularly relevant for a terminal emulator. */

#if 0 /* gl.w */
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
#endif

        /* Again mostly useful for 3D rendering, but used here to
                render in ``layers'' so that the glyphs can be
                placed ``on top'' of a background layer. */

        glEnable(GL_DEPTH_TEST);
        glDepthMask(GL_TRUE);
        glDepthFunc(GL_LEQUAL);
        glDepthRange(0.0f, 1.0f);
        glEnable(GL_DEPTH_CLAMP);

        /* Specify what blank looks like. */

        glClearColor(0.333, 0.499, 0.666, 1.0);
        glClearDepth(10.0f);

        @<Prepare a Vertex Array Object (VAO)@>@;

        cgl_load_shader_program();
        cgl_report_errors("cgl_load_shader_program");
        inform("Compiled & linked shaders");
}

@ This is overkill for this application which only renders a single
thing but a useful concept to be familiar with.

In order to push data to OpenGL or tell it to do something with it,
it must be informed about a number of data buffers pertaining to
vertices, textures, programs in the rendering pipeline etc. A Vertex
Array Object (VAO) is a set of these bindings. A single VAO is
created here binding two buffers: One of vertices (the corners of
each character on the screen) and one of pointers to these vertices.

The texture should probably be bound here but I'm still a bit hazy
on how VAOs and bindings work and textures are weirder still.

The |glEnableVertexAttribArray| and |glVertexAttribPointer| calls
describe the layout of the vertex data in each |cgl_vertex|.

@<Prepare a Vertex Array Object (VAO)@>=
Draw_Buffer = vector_new(sizeof (cgl_vertex));
Draw_Index = vector_new(sizeof (GLushort));
glGenVertexArrays(1, &VAO); /* A bit pointless */
glGenBuffers(2, VBO);
glBindVertexArray(VAO); {
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, VBO[0]);
        glBindBuffer(GL_ARRAY_BUFFER, VBO[1]);
        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        glEnableVertexAttribArray(2);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof (cgl_vertex),
                (void *) offsetof (cgl_vertex, pos));
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof (cgl_vertex),
                (void *) offsetof (cgl_vertex, tex));
        glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof (cgl_vertex),
                (void *) offsetof (cgl_vertex, col));
} glBindVertexArray(0);

@ What is this for? Does fuck all.

@c
void
cgl_glerror (int         code unused,
             const char *msg)
{
        fputs("wtf?\n", stderr);
        fputs(msg, stderr);
}

@ @c
void
cgl_report_errors (char *msg)
{
        for (GLenum f = glGetError(); f != GL_NO_ERROR; f = glGetError())
                complain("%s: %s", msg, gluErrorString(f));
}

@ @c
void
cgl_cb_debug (GLenum        source   unused,
              GLenum        type,
              unsigned int  id       unused,
              GLenum        severity,
              GLsizei       length   unused,
              const char   *message,
              const void   *arg      unused)
{
        complain("GL CALLBACK: %s type = 0x%x, severity = 0x%x, message = %s\n",
                (type == GL_DEBUG_TYPE_ERROR ? "ERROR" : ""),
                type, severity, message);
        return;
}

@ @c
void
cgl_window (int w,
            int h)
{
        GLFWwindow *new_win;

        assert(Win == NULL);
        glfwWindowHint(GLFW_VISIBLE, GL_TRUE);
        glfwWindowHint(GLFW_RESIZABLE, GL_TRUE);
        glfwWindowHint(GLFW_SCALE_TO_MONITOR, GLFW_TRUE); /* Maybe? */
        glfwWindowHintString(GLFW_X11_CLASS_NAME, "TurTle");
        glfwWindowHintString(GLFW_X11_INSTANCE_NAME, Win_Name);
        if (Debug)
                glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GLFW_TRUE);
#if 0 /* What do these do? */
        glfwWindowHint(GLFW_CONTEXT_ROBUSTNESS, ...); /* ? */
        glfwWindowHint(GLFW_CONTEXT_RELEASE_BEHAVIOR, ...); /* ? */
        glfwWindowHintString(GLFW_COCOA_FRAME_NAME, Win_Name); /* Window snapshot? */
#endif
        glfwWindowHint(GLFW_COCOA_GRAPHICS_SWITCHING, GLFW_TRUE); /* Permit low-power GPU. */

        new_win = glfwCreateWindow(w, h, Win_Name, NULL, NULL);
        if (new_win == NULL) {
                const char* description;
                int code = glfwGetError(&description);
                errx(1, "glfwCreateWindow %d: %s", code, description);
        }
        inform("Created %ux%u window", w, h);

        glfwSetFramebufferSizeCallback(new_win, cgl_cb_resize);
        glfwSetWindowCloseCallback(new_win, cgl_cb_close);

        glfwMakeContextCurrent(new_win);
        Win = new_win;
}

@ @c
static void
cgl_cb_close (GLFWwindow *glwin)
{
        assert(glwin == Win);
        io_stop();
}

@* Drawing.

A pipeline is configured. Vertices are created by the application
and sent to OpenGL. The pipeline is constructed is misnamed ``shaders''
which are programs that run on the GPU.

Each time the screen is rendered each vertex is run through the
{\it vertex shader\/} to calculate the final position from it's own
3D co-ordinates to a framebuffer's 2D co-ordinates.

After the vertices are processed OpenGL does its thing and calculates
fragments. Fragments can be thought of as the individual pixels in
the framebuffer but that's not quite right. In particular fragments
can be smaller than pixels and the actual pixel data is calculated
from the fragments accordingly.

Each fragment is processed by a {\it fragment shader\/} which is
primarily concerned with calculating a pixel's colour.

@ This is the vertex shader. The input vertices are spread between
three variables at hard-coded locations 0, 1 and 2.

The colout and texture data from the vertex is simply assigned to
output variables |ex_col| and |ex_tex|. These will be supplied as
input variables to the fragment shader for this vertex. The real
position of the vertex is returned in |gl_Position|.

@(vertex.glsl@>=
uniform mat4 projection;

layout(location = 0) in vec3 vx;@;
layout(location = 1) in vec2 tex;@;
layout(location = 2) in vec3 col;@;

out vec4 ex_col;
out vec2 ex_tex;

void main()
{
        ex_col      = vec4(col, 1);
        ex_tex      = tex;
        gl_Position = projection * vec4(vx, 1.0);
}

@ The fragment shader works out what colour each pixel should be.
Given a triangle representing half of a glyph, OpenGL has already
worked out where within that triangle the fragment is.

If the texture co-ordinates are negative then this fragment represents
a solid colour such as the background or the cursor. Otherise it's
a glyph and the texture co-ordinates refer to a pixel in the font
atlas.

@(fragment.glsl@>=
uniform sampler2D atlas;

in vec4 ex_col;
in vec2 ex_tex;

out vec4 frag;

void main()
{
        if (ex_tex.x >= 0 && ex_tex.y >= 0)
                frag = texture(atlas, ex_tex);
        else
                frag = ex_col;
}

@ These routines are concerned with loading the above shader sources
and compiling and linking to the GPU during initialisation.

@<GL global...@>=
#include "vertex.c" /* Defines |Source_vertex| \AM\ |Source_vertex_Length|. */
#include "fragment.c" /* Defines |Source_fragment| \AM\ |Source_fragment_Length|. */

@ The |GL_ARB_shading_language_include| extension included here
with each shader allows it to be compiled from the source code in
this \.{CWEB} document and still report the correct line numbers
thanks to Donald Knuth's meticulous attention to detail.

@d SHADER_HEADER ""@|
        "#version 330 core\n"@|
        "#extension GL_ARB_shading_language_include : require\n"
@c
GLuint
cgl_compile_shader (GLenum  type,
                    char   *source,
                    long    length)
{
        const GLchar *cat[2] = { SHADER_HEADER, source };
        GLint clen[2] = { strlen(SHADER_HEADER), length };
        GLint status;
        GLuint s;

        s = glCreateShader(type);
        glShaderSource(s, 2, cat, clen);
        glCompileShader(s);

        glGetShaderiv(s, GL_COMPILE_STATUS, &status);
        if (status == GL_FALSE) {
                GLchar msg[256];
                glGetShaderInfoLog(s, sizeof (msg), 0, msg);
                errx(1, "%s", msg);
        }

        return s;
}

@ There is only one shader pipeline program with the two shaders above.

@c
void
cgl_load_shader_program (void)
{
        GLint status;
        GLuint f, p, v;

        if (!glewIsSupported("GL_ARB_shading_language_include"))
                errx(1, "GL_ARB_shading_language_include unsupported");

        p = glCreateProgram();
        v = cgl_compile_shader(GL_VERTEX_SHADER, Source_vertex,
                Source_vertex_Length);
        f = cgl_compile_shader(GL_FRAGMENT_SHADER, Source_fragment,
                Source_fragment_Length);
        glAttachShader(p, v);
        glAttachShader(p, f);
        glLinkProgram(p);
        glGetProgramiv(p, GL_LINK_STATUS, &status);
        if (status == GL_FALSE) {
                GLchar msg[256];
                glGetProgramInfoLog(p, sizeof (msg), 0, msg);
                errx(1, "%s", msg);
        }

        Shader_Program = p;
        glDeleteShader(v);
        glDeleteShader(f);
}

@ As an homage to simpler machines from the before times the routine
which performs every screen draw is named ``blit''. This is the
routine run $n$ times every second which redraws the screen contents.

The process used by this application is that the frame buffer is
cleared; if the vertex data has changed then the new texture and
vertex buffer data is pushed to OpenGL; the pipeline is run to
render each vertex to a collection of fragments and thence to pixels;
the screen's active framebuffer and the framebuffer just drawn on
to are swapped, updating the display.

@c
void
cgl_blit (void)
{
        assert(glGetError() == GL_NO_ERROR);

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        glUseProgram(Shader_Program);

        glBindVertexArray(VAO); {
                if (1) { /* dirty */
                        glBindTexture(GL_TEXTURE_2D, Glyph_Atlas->id);
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,
                                GL_CLAMP_TO_EDGE);
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,
                                GL_CLAMP_TO_EDGE);
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,
                                GL_LINEAR);
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                                GL_LINEAR);
                        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA,
                                Glyph_Atlas->width, Glyph_Atlas->height, 0,
                                GL_RGBA, GL_UNSIGNED_BYTE, Glyph_Atlas->data);

                        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, VBO[0]);
                        glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                                vector_size(Draw_Index) * sizeof (GLushort),
                                Draw_Index->items, GL_STATIC_DRAW);
                        glBindBuffer(GL_ARRAY_BUFFER, VBO[1]);
                        glBufferData(GL_ARRAY_BUFFER,
                                vector_size(Draw_Buffer) * sizeof (cgl_vertex),
                                Draw_Buffer->items, GL_STATIC_DRAW);
                }

                glUniformMatrix4fv(glGetUniformLocation(Shader_Program, "projection"),
                        1, 0, (GLfloat *) &Projection);
                glDrawElements(GL_TRIANGLES, vector_size(Draw_Index), GL_UNSIGNED_SHORT, 0);
        } glBindVertexArray(0);

        cgl_report_errors("cgl_render");

        glfwSwapBuffers(Win);
}

@ This routine is called when the terminal's contents have been
changed and the vertex data representing them needs to be re-done.

It includes a commented-out debugging triangle instruction in the
first 3 indices.

@c
void
cgl_clear_vertex_buffer (void)
{
        vector_clear(Draw_Buffer);
        vector_clear(Draw_Index);
#if 0
                        GLushort i[] = { 0, 1, 2 };
                        cgl_vertex v[] = {@|
                                { { 10.0f, 10.0f, 0.0f }, { 0,0 }, { 1,1,1 } },@|
                                { {100.0f, 10.0f, 0.0f }, { 0,0 }, { 1,1,1 } },@|
                                { { 10.0f,100.0f, 0.0f }, { 0,0 }, { 1,1,1 } },@/
                        };
                        vector_push_back_data(Draw_Buffer, v, sizeof (v) / sizeof (v[0]));
                        vector_push_back_data(Draw_Index, i, sizeof (i) / sizeof (i[0]));
#endif
}

@* Fonts. A font definition contains instructions to render the
glyphs within that font at, usually, many font-sizes rather than
containing a single set of instructions that are stretched as
appropriate (it would look awful).

When a font is loaded at a particular size the font is scanned to determine
the size of each character cell on the terminal's screen.

The method here is crude but effective for the time being: it scans
each of the extended ASCII characters for its width and other
characteristics to determine the maximum size of each cell and the
offset of each character's glyph within it.

@c
cgl_face
cgl_load_font (char   *name,
               size_t  size)
{
        cgl_face newface;
        texture_glyph_t *glyph;
        float vwidth;
        int cwidth, height, descent, offset, nheight, ndescent, noffset;

        newface.m.family  = name;
        newface.m.size    = size;
        newface.m.gamma   = 1.0;
        newface.m.colour  = vec4(0, 0, 0, 1);
        newface.m.font    = texture_font_new_from_file(Glyph_Atlas, size, newface.m.family);
        if (newface.m.font == NULL)
                err(1, "texture_font_new_from_file");

        vwidth = cwidth = height = descent = offset = 0;
        for (int i = ' '; i < 256; i++) {
                glyph = texture_font_get_glyph(newface.m.font, i);
                if (glyph == NULL)
                        err(1, "texture_font_get_glyph");
                vwidth += glyph->advance_x;
                if (glyph->width > cwidth)
                        cwidth = glyph->width;

                if (glyph->offset_y < 0) {/* descends only */
                        nheight = ndescent = -glyph->offset_y + glyph->height;
                        noffset = 0;
                } else if (glyph->height < glyph->offset_y) {/* ascends only */
                        nheight = noffset = glyph->offset_y;
                        ndescent = 0;
                } else {
                        nheight = noffset = glyph->offset_y;
                        ndescent = glyph->height - noffset;
                }
                if (ndescent > descent)
                        descent = ndescent;
                if (noffset > offset)
                        offset = noffset;
                if (nheight > height)
                        height = nheight;
        }
        vwidth /= 256 - ' ';
        if (vwidth - glyph->advance_x)
                complain("Variable width font: average %f", vwidth);
        inform("Loaded %zupt `%s' font, size %ux%u (%.2fx%.2f) + %.2f",
                size, name, (int) cwidth, (int) ceilf(height), vwidth,
                height, offset);
        newface.width  = cwidth;
        newface.height = descent + height;
        newface.inset  = descent;
        return newface;
}

@ The framebuffer that OpenGL finally draws is expected to have its
contents between -1 and 1 on the X and Y axes with the origin in
the centre of the screen or window.

This application does not render a 3D scene so the co-ordinates it
draws into are closely related to the screen co-ordinates (there
is some inversion). The Z co-ordinate included with each vertex
represents a screen ``layer'' with higher values toward the viewer.

The vertex shader takes these mostly-real co-ordinates and transforms
them to fragments in OpenGL's -1 .. 1 space where the fragment
shader can colour them in. The bits of the pipeline that you don't
see then take these coloured in fragments and convert them to screen
co-ordinates to paint with.

That explanation needs some work. In any case the matrix in
|Projection| is the means by which glyph vertices are transformed
into OpenGL vertices. It's changed whenever the window is resized
and uploaded to OpenGL during |cgl_blit|.

@<GL global...@>=
mat4_t Projection;

@ @<GL shared...@>=
extern mat4_t Projection;

@ @c
void
cgl_cb_resize (GLFWwindow *glwin,
               int         w,
               int         h)
{
        assert(glwin == Win);
        glViewport(0, 0, w, h);
        Projection = m4_ortho(0, w, 0, h, -1, 1);
        term_resize(w / (int) Face[FACE_NORMAL].width,
                h / (int) Face[FACE_NORMAL].height);
        inform("Resize window to %ux%u (%ux%u)", w, h,
                w / (int) Face[FACE_NORMAL].width,
                h / (int) Face[FACE_NORMAL].height);
}

@ ``Drawing'' a glyph within a cell means pushing vertices to the
back of |Draw_Buffer| and pointers to those vertices in |Draw_Index|.
After all the cells of the terminal have been drawn in such a way
the vertex data will be pushed to OpenGL which will draw it as
described above.

@c
void
cgl_draw_glyph (int      x,
                int      y,
                bvec3_t  bg,
                bvec3_t  fg,
                int      f,
                trt_rune p,
                trt_rune u)
{
        texture_glyph_t *glyph;
        vec2_t bbl, btr, fbl,ftr;

        assert(f >= 0 && f < FACE_LENGTH);

        bbl.x = x * Face[FACE_NORMAL].width;
        bbl.y = y * Face[FACE_NORMAL].height;
        btr.x = (x + 1) * Face[FACE_NORMAL].width;
        btr.y = (y + 1) * Face[FACE_NORMAL].height;

        glyph = texture_font_get_glyph(Face[f].m.font, u);

        fbl.x = bbl.x + glyph->offset_x;
        fbl.y = bbl.y + Face[f].inset;
        fbl.y += glyph->offset_y - (int) glyph->height;
        ftr.x = fbl.x + glyph->width;
        ftr.y = fbl.y + glyph->height;

#if 0
        assert(fbl.x >= bbl.x); assert(fbl.x <= btr.x);
        assert(ftr.x >= bbl.x); assert(ftr.x <= btr.x);
        assert(fbl.y >= bbl.y); assert(fbl.y <= btr.y);
        assert(ftr.y >= bbl.y); assert(ftr.y <= btr.y);
#endif

        float s0 = glyph->s0;
        float t0 = glyph->t0;
        float s1 = glyph->s1;
        float t1 = glyph->t1;

        cgl_vertex v[] = {@|
                { { bbl.x, bbl.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },@|
                { { btr.x, bbl.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },@|
                { { bbl.x, btr.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },@|
                { { btr.x, btr.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },@|
                { { fbl.x, fbl.y, 0 }, { s0, t1 }, { fg.x, fg.y, fg.z } },@|
                { { ftr.x, fbl.y, 0 }, { s1, t1 }, { fg.x, fg.y, fg.z } },@|
                { { fbl.x, ftr.y, 0 }, { s0, t0 }, { fg.x, fg.y, fg.z } },@|
                { { ftr.x, ftr.y, 0 }, { s1, t0 }, { fg.x, fg.y, fg.z } },@/
        };
        int s = vector_size(Draw_Buffer);
        assert(s < 0xFFFF - 8);
        GLushort i[] = {@|
                s+0,s+1,s+2, s+1,s+3,s+2,@|
                s+4,s+5,s+6, s+5,s+7,s+6,@/
        };
        vector_push_back_data(Draw_Buffer, v, sizeof (v) / sizeof (v[0]));
        vector_push_back_data(Draw_Index, i, sizeof (i) / sizeof (i[0]));
}

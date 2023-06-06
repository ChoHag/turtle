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
#include "ft/markup.h"
@h
@<GL type definitions@>@;
@<GL shared variables@>@;
@<GL function declarations@>@;
#endif /* |TRT_CGL_H| */

@ @(cgl-opengl.h@>=
#ifndef TRT_OPENGL_H
#define TRT_OPENGL_H

#include <GL/glew.h>
#if defined(_WIN32) || defined(_WIN64)
#  include <GL/wglew.h>
#endif

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#endif /* |TRT_OPENGL_H| */

@ @<GL type def...@>=
enum {
        FACE_NORMAL,
        FACE_LENGTH
};

typedef struct {
        markup_t m;
        float width, height, inset;
} cgl_face;

typedef struct {
        vec3_t pos;
        vec2_t tex;
        vec3_t col;
} cgl_vertex;

@ @<GL global...@>=
vector_xt *Draw_Buffer, *Draw_Index;
cgl_face Face[FACE_LENGTH];
texture_atlas_t *Glyph_Atlas;
GLuint Shader_Program;
GLuint VAO;
GLuint VBO[2];
GLFWwindow *Win;

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

@ @c
void
cgl_init (int w,
          int h,
          int font_size)
{
        int flags;

        Glyph_Atlas = texture_atlas_new(512, 512, 4);
        if (Glyph_Atlas == NULL)
                err(1, "texture_font_get_glyph");
        glGenTextures(1, &Glyph_Atlas->id);
        Face[FACE_NORMAL] = cgl_load_font("VeraMono.ttf", font_size * 3);

        glfwSetErrorCallback(cgl_glerror);
        if (!glfwInit())
                errx(1, "glfwInit");
        inform("Using GLFW %s", glfwGetVersionString());

        cgl_window(w, h);
        cgl_report_errors("cgl_window");

        if (glewInit() != GLEW_OK)
                errx(1, "glewInit"); /* {\it After\/} the window is opened. */
        inform("Using GLEW %s", glewGetString(GLEW_VERSION));

        glGetIntegerv(GL_CONTEXT_FLAGS, &flags);
        if (flags & GL_CONTEXT_FLAG_DEBUG_BIT) {
                glEnable(GL_DEBUG_OUTPUT);
                glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
                glDebugMessageCallback(cgl_cb_debug, NULL);
                glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE,
                        GL_DONT_CARE, 0, NULL, GL_TRUE);
        }

#if 0 /* gl.w */
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        glFrontFace(GL_CW);
#endif

#if 0 /* gl.w */
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
#endif

        glEnable(GL_DEPTH_TEST);
        glDepthMask(GL_TRUE);
        glDepthFunc(GL_LEQUAL);
        glDepthRange(0.0f, 1.0f);
        glEnable(GL_DEPTH_CLAMP);

        glClearColor(0.333, 0.499, 0.666, 1.0);
        glClearDepth(10.0f);

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

        cgl_load_shader_program();
        cgl_report_errors("cgl_load_shader_program");
        inform("Compiled & linked shaders");
}

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

@ TODO: Trigger reszie event upon creation.

@.TODO@>
@c
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

@(vertex.glsl@>=
uniform mat4 projection;

layout(location = 0) in vec3 vx;
layout(location = 1) in vec2 tex;
layout(location = 2) in vec3 col;

out vec4 ex_col;
out vec2 ex_tex;

void main()
{
        ex_col      = vec4(col, 1);
        ex_tex      = tex;
        gl_Position = projection * vec4(vx, 1.0);
}

@ @(fragment.glsl@>=
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

@ @<GL global...@>=
#include "vertex.c" /* Defines |Source_vertex| \AM\ |Source_vertex_Length|. */
#include "fragment.c" /* Defines |Source_fragment| \AM\ |Source_fragment_Length|. */

@ @c
#define SHADER_HEADER                                           \
        "#version 330 core\n"                                   \
        "#extension GL_ARB_shading_language_include : require\n"
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

@ @c
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

@ @c
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

@ @c
void
cgl_clear_vertex_buffer (void)
{
        vector_clear(Draw_Buffer);
        vector_clear(Draw_Index);
#if 0
                        GLushort i[] = { 0, 1, 2 };
                        cgl_vertex v[] = {
                                { { 10.0f, 10.0f, 0.0f }, { 0,0 }, { 1,1,1 } },
                                { {100.0f, 10.0f, 0.0f }, { 0,0 }, { 1,1,1 } },
                                { { 10.0f,100.0f, 0.0f }, { 0,0 }, { 1,1,1 } },
                        };
                        vector_push_back_data(Draw_Buffer, v, sizeof (v) / sizeof (v[0]));
                        vector_push_back_data(Draw_Index, i, sizeof (i) / sizeof (i[0]));
#endif
}

@* Fonts.

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

@ @<GL global...@>=
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

@ @c
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

        cgl_vertex v[] = {
                { { bbl.x, bbl.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },
                { { btr.x, bbl.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },
                { { bbl.x, btr.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },
                { { btr.x, btr.y,-1 }, { -1, -1 }, { bg.x, bg.y, bg.z } },
                { { fbl.x, fbl.y, 0 }, { s0, t1 }, { fg.x, fg.y, fg.z } },
                { { ftr.x, fbl.y, 0 }, { s1, t1 }, { fg.x, fg.y, fg.z } },
                { { fbl.x, ftr.y, 0 }, { s0, t0 }, { fg.x, fg.y, fg.z } },
                { { ftr.x, ftr.y, 0 }, { s1, t0 }, { fg.x, fg.y, fg.z } },
        };
        int s = vector_size(Draw_Buffer);
        assert(s < 0xFFFF - 8);
        GLushort i[] = {
                s+0,s+1,s+2, s+1,s+3,s+2,
                s+4,s+5,s+6, s+5,s+7,s+6,
        };
        vector_push_back_data(Draw_Buffer, v, sizeof (v) / sizeof (v[0]));
        vector_push_back_data(Draw_Index, i, sizeof (i) / sizeof (i[0]));
}

@i types.w
\font\sc=cmcsc10

Copied from freetype-gl at \.{https://github.com/rougier/freetype-gl.git}
whence it was ``distributed under the OSI-approved BSD 2-Clause
License'' included below:

Copyright \copyright\ 2011-2016 Nicolas P. Rougier\par
Copyright \copyright\ 2013-2016 Marcel Metz\par
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer\footnote{$^1$}{There
    are now two disclaimers...}.

 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.

{\sc This software is provided by the copyright holders and contributors ``as is''
and any express or implied warranties, including, but not limited to, the
implied warranties of merchantability and fitness for a particular purpose are
disclaimed. In no event shall the copyright holders or contributors be liable
for any direct, indirect, incidental, special, exemplary, or consequential
damages (including, but not limited to, procurement of substitute goods or
services; loss of use, data, or profits; or business interruption) however
caused and on any theory of liability, whether in contract, strict liability,
or tort (including negligence or otherwise) arising in any way out of the use
of this software, even if advised of the possibility of such damage.}

The views and conclusions contained in the software and documentation are
those of the authors and should not be interpreted as representing official
policies, either expressed or implied, of the freetype-gl project.

@ TODO:

Finish importing \.{vector.h}.

Index.

Custom/no allocator.

@** Dynamic vector.

@c
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
@#
#include "vector.h"

@ The include guard was originally named |__VECTOR_H__| which is
(I think) reserved by the \CEE/ standard. Plain |VECTOR_H| is too
likely to clash so the prefix \.{FTGL} reflects the original source
of this source code.

@(vector.h@>=
#ifndef FTGL_VECTOR_H
#define FTGL_VECTOR_H

#ifdef __cplusplus
extern "C" {
#endif

@<Vector type definition@>@;

@<Vector API@>@;

#ifdef __cplusplus
}
#endif

#endif /* |FTGL_VECTOR_H| */

@ The type definition is straightforward but has also been renamed
as the \.{\_t} suffix is another reserved name.

@<Vector type...@>=
typedef struct vector_xt {
        void *items;      /* Pointer to dynamically allocated items. */
        size_t capacity;  /* Number of items that can be held in
                                currently allocated storage. */
        size_t size;      /* Number of items. */
        size_t item_size; /* Size (in bytes) of a single item. */
} vector_xt;

@ @<Vector API@>=
void *vector_back (const vector_xt *);
size_t vector_capacity (const vector_xt *);
void vector_clear (vector_xt *);
void vector_delete (vector_xt *);
int vector_empty (const vector_xt *);
void *vector_front (const vector_xt *);
void *vector_get (const vector_xt *, size_t);
vector_xt *vector_new (size_t);
void vector_reserve (vector_xt *, size_t);
void vector_resize (vector_xt *, const size_t);
void vector_set (vector_xt *, const size_t, const void *);
void vector_shrink (vector_xt *);
size_t vector_size (const vector_xt *);

@ @c
vector_xt *
vector_new( size_t item_size )
{
    vector_xt *self = (vector_xt *) malloc( sizeof(vector_xt) );
    assert( item_size );

    if( !self )
	return NULL;
    self->item_size = item_size;
    self->size      = 0;
    self->capacity  = 1;
    self->items     = calloc( self->item_size, self->capacity );
    return self;
}

@ @c
void
vector_delete( vector_xt *self )
{
    assert( self );

    free( self->items );
    free( self );
}

@ @c
void *
vector_get( const vector_xt *self,
            size_t index )
{
    assert( self );
    assert( self->size );
    assert( index  < self->size );

    return (char*)(self->items) + index * self->item_size;
}

@ @c
void *
vector_front( const vector_xt *self )
{
    assert( self );
    assert( self->size );

    return vector_get( self, 0 );
}

@ @c
void *
vector_back( const vector_xt *self )
{
    assert( self );
    assert( self->size );

    return vector_get( self, self->size-1 );
}

@ @c
int
vector_empty( const vector_xt *self )
{
    assert( self );

    return self->size == 0;
}

@ @c
size_t
vector_size( const vector_xt *self )
{
    assert( self );

    return self->size;
}

@ @c
void
vector_reserve( vector_xt *self,
                size_t size )
{
    assert( self );

    if( self->capacity < size)
    {
        self->items = realloc( self->items, size * self->item_size );
	memset( (char *)(self->items) + self->capacity * self->item_size, 0,
		(size - self->capacity) * self->item_size );
        self->capacity = size;
    }
}

@ @c
size_t
vector_capacity( const vector_xt *self )
{
    assert( self );

    return self->capacity;
}

@ @c
void
vector_shrink( vector_xt *self )
{
    assert( self );

    if( self->capacity > self->size )
    {
        self->items = realloc( self->items, self->size * self->item_size );
    }
    self->capacity = self->size;
}

@ @c
void
vector_clear( vector_xt *self )
{
    assert( self );

    memset( (char *)(self->items), 0, self->size * self->item_size);
    self->size = 0;
}

@ @c
void
vector_set( vector_xt *self,
            const size_t index,
            const void *item )
{
    assert( self );
    assert( self->size );
    assert( index  < self->size );

    memcpy( (char *)(self->items) + index * self->item_size,
            item, self->item_size );
}

@* More complex functions.

@<Vector API@>=
int vector_contains (const vector_xt *, const void *,
        int (*)(const void *, const void *));
void vector_erase (vector_xt *, const size_t);
void vector_erase_range (vector_xt *, const size_t, const size_t);
void vector_insert (vector_xt *, const size_t, const void *);
void vector_insert_data (vector_xt *, const size_t, const void *, const size_t);
void vector_pop_back (vector_xt *);
void vector_push_back (vector_xt *, const void *);
void vector_push_back_data (vector_xt *, const void *, const size_t);
void vector_sort (vector_xt *, int (*)(const void *, const void *));

@ @c
int
vector_contains( const vector_xt *self,
                 const void *item,
                 int (*cmp)(const void *, const void *) )
{
    size_t i;
    assert( self );

    for( i=0; i<self->size; ++i )
    {
        if( (*cmp)(item, vector_get(self,i) ) == 0 )
        {
            return 1;
        }
    }
   return 0;
}

@ @c
void
vector_insert( vector_xt *self,
               const size_t index,
               const void *item )
{
    assert( self );
    assert( index <= self->size);

    if( self->capacity <= self->size )
    {
        vector_reserve(self, 2 * self->capacity );
    }
    if( index < self->size )
    {
        memmove( (char *)(self->items) + (index + 1) * self->item_size,
                 (char *)(self->items) + (index + 0) * self->item_size,
                 (self->size - index)  * self->item_size);
    }
    self->size++;
    vector_set( self, index, item );
}

@ @c
void
vector_erase_range( vector_xt *self,
                    const size_t first,
                    const size_t last )
{
    assert( self );
    assert( first < self->size );
    assert( last  < self->size+1 );
    assert( first < last );

    memmove( (char *)(self->items) + first * self->item_size,
             (char *)(self->items) + last  * self->item_size,
             (self->size - last)   * self->item_size);
    self->size -= (last-first);
}

@ @c
void
vector_erase( vector_xt *self,
              const size_t index )
{
    assert( self );
    assert( index < self->size );

    vector_erase_range( self, index, index+1 );
}

@ @c
void
vector_push_back( vector_xt *self,
                  const void *item )
{
    vector_insert( self, self->size, item );
}

@ @c
void
vector_pop_back( vector_xt *self )
{
    assert( self );
    assert( self->size );

    self->size--;
}

@ @c
void
vector_resize( vector_xt *self,
               const size_t size )
{
    assert( self );

    if( size > self->capacity)
    {
        vector_reserve( self, size );
        self->size = self->capacity;
    }
    else
    {
        self->size = size;
    }
}

@ @c
void
vector_push_back_data( vector_xt *self,
                       const void * data,
                       const size_t count )
{
    assert( self );
    assert( data );
    assert( count );

    if( self->capacity < (self->size+count) )
    {
        vector_reserve(self, self->size+count);
    }
    memmove( (char *)(self->items) + self->size * self->item_size, data,
             count*self->item_size );
    self->size += count;
}

@ @c
void
vector_insert_data( vector_xt *self,
                    const size_t index,
                    const void * data,
                    const size_t count )
{
    assert( self );
    assert( index < self->size );
    assert( data );
    assert( count );

    if( self->capacity < (self->size+count) )
    {
        vector_reserve(self, self->size+count);
    }
    memmove( (char *)(self->items) + (index + count ) * self->item_size,
             (char *)(self->items) + (index ) * self->item_size,
             count*self->item_size );
    memmove( (char *)(self->items) + index * self->item_size, data,
             count*self->item_size );
    self->size += count;
}

@ @c
void
vector_sort( vector_xt *self,
             int (*cmp)(const void *, const void *) )
{
    assert( self );
    assert( self->size );

    qsort(self->items, self->size, self->item_size, cmp);
}

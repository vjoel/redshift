#include "ruby.h"
#include "rand.h"

#ifndef min
# define min(a,b) (((a)<(b)) ? (a) : (b))
#endif /* min */

static VALUE
ISAAC_s_allocate(VALUE klass)
{
    randctx *ctx;

    return Data_Make_Struct(klass, randctx, NULL, NULL, ctx);
}

/*
 * Seed the generator with an array of up to ISAAC::RANDSIZ integers in the
 * range 0..2**32-1. More entries are ignored. Missing entries are treated
 * as 0. Returns +nil+.
 */
static VALUE
ISAAC_srand(VALUE self, VALUE ary)
{
    int i;
    randctx *ctx;

    Check_Type(ary, T_ARRAY);
    
    Data_Get_Struct(self, randctx, ctx);
    
    MEMZERO(ctx, randctx, 1);
    for (i=min(RANDSIZ, RARRAY_LEN(ary))-1; i>=0; i--) {
        ctx->randrsl[i] = NUM2UINT(RARRAY_PTR(ary)[i]);
    }
    rs_isaac_init(ctx, 1);

    return Qnil;
}

/*
 * Return a random integer in the range 0..2**32-1.
 */
static VALUE
ISAAC_rand32(VALUE self)
{
    randctx *ctx;

    Data_Get_Struct(self, randctx, ctx);

    if (!ctx->randcnt--) {
        rs_isaac_rand(ctx);
        ctx->randcnt=RANDSIZ-1;
    }
    
    return UINT2NUM(ctx->randrsl[ctx->randcnt]);
}

/*
 * Return a random float in the range 0..1.
 */
static VALUE
ISAAC_rand(VALUE self)
{
    randctx *ctx;

    Data_Get_Struct(self, randctx, ctx);

    if (!ctx->randcnt--) {
        rs_isaac_rand(ctx);
        ctx->randcnt=RANDSIZ-1;
    }
    
    return rb_float_new(ctx->randrsl[ctx->randcnt] / 4294967295.0);
}

static VALUE
ISAAC_marshal_dump(VALUE self)
{
    randctx *ctx;
    int i;
    int ary_size = sizeof(randctx)/sizeof(ub4);
    VALUE ary;

    Data_Get_Struct(self, randctx, ctx);
    
    ary = rb_ary_new2(ary_size);
    for (i = 0; i < ary_size; i++) {
        rb_ary_push(ary, UINT2NUM(((ub4 *)ctx)[i]));
    }
    
    return ary;
}

static VALUE
ISAAC_marshal_load(VALUE self, VALUE ary)
{
    randctx *ctx;
    int i;
    int ary_size = sizeof(randctx)/sizeof(ub4);

    Data_Get_Struct(self, randctx, ctx);

    if (RARRAY_LEN(ary) != ary_size)
        rb_raise(rb_eArgError, "bad length in loaded ISAAC data");

    for (i = 0; i < ary_size; i++) {
        ((ub4 *)ctx)[i] = NUM2UINT(RARRAY_PTR(ary)[i]);
    }
    
    return self;
}

void
Init_isaac()
{
    VALUE ISAAC;

    ISAAC = rb_define_class("ISAAC", rb_cObject);
    rb_define_alloc_func(ISAAC, ISAAC_s_allocate);
    rb_define_method(ISAAC, "srand", ISAAC_srand, 1);
    rb_define_method(ISAAC, "rand32", ISAAC_rand32, 0);
    rb_define_method(ISAAC, "rand", ISAAC_rand, 0);
    rb_define_method(ISAAC, "marshal_dump", ISAAC_marshal_dump, 0);
    rb_define_method(ISAAC, "marshal_load", ISAAC_marshal_load, 1);
    
    rb_const_set(ISAAC, rb_intern("RANDSIZ"), UINT2NUM(RANDSIZ));
}

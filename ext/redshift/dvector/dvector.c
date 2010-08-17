#include "dvector.h"

static void dv_mark(RS_DVector *dv)
{
    long i;
    if (dv->ptr) {
        for (i=0; i < dv->len; i++) {
            rb_gc_mark(dv->ptr[i]);
        }
    }
}

static void dv_free(RS_DVector *dv)
{
    free(dv->ptr);
    free(dv);
}

static VALUE dv_alloc(VALUE klass)
{
    VALUE self;
    RS_DVector *dv;
    
    self = Data_Make_Struct(klass, RS_DVector, dv_mark, dv_free, dv);

    dv->len = 0;
    dv->capa = 0;
    dv->ptr = 0;
    
    return self;
}

void rs_dv_grow(RS_DVector *dv)
{
    if (!dv->ptr) {
        dv->capa = 16;
        dv->ptr = ALLOC_N(VALUE, dv->capa);
    }
    else if (dv->len == dv->capa) {
        dv->capa *= 2;
        REALLOC_N(dv->ptr, VALUE, dv->capa);
    }
}

void rs_dv_shrink(RS_DVector *dv)
{
    if (dv->ptr && dv->len < dv->capa) {
        REALLOC_N(dv->ptr, VALUE, dv->len);
        dv->capa = dv->len;
    }
}

static VALUE dv_method_push(int argc, VALUE *argv, VALUE self)
{
    int i;
    RS_DVector *dv;
    
    Data_Get_Struct(self, RS_DVector, dv);
    
    for (i = 0; i < argc; i++) {
        rs_dv_push(dv, argv[i]);
    }

    return self;
}

static VALUE dv_method_pop(VALUE self)
{
    RS_DVector *dv;
    
    Data_Get_Struct(self, RS_DVector, dv);

    return rs_dv_pop(dv);    
}

static VALUE dv_method_each(VALUE self)
{
    long i;
    RS_DVector *dv;
    
    Data_Get_Struct(self, RS_DVector, dv);

    RETURN_ENUMERATOR(self, 0, 0);
    for (i=0; i < dv->len; i++) {
	rb_yield(dv->ptr[i]);
    }
    
    return self;
}

static VALUE dv_method_to_a(VALUE self)
{
    RS_DVector *dv;
    Data_Get_Struct(self, RS_DVector, dv);
    return dv->ptr ? rb_ary_new4(dv->len, dv->ptr) : rb_ary_new();
}

static VALUE dv_method_length(VALUE self)
{
    RS_DVector *dv;
    Data_Get_Struct(self, RS_DVector, dv);
    return INT2NUM(dv->len);
}

static VALUE recursive_equal(VALUE self, VALUE other, int recur)
{
    long i;
    RS_DVector *dv1, *dv2;

    Data_Get_Struct(self, RS_DVector, dv1);
    Data_Get_Struct(other, RS_DVector, dv2);

    if (recur) return Qfalse;
    for (i=0; i < dv1->len; i++) {
        if (!rb_equal(dv1->ptr[i], dv2->ptr[i]))
            return Qfalse;
    }
    return Qtrue;
}

static VALUE dv_method_equal(VALUE self, VALUE other)
{
    RS_DVector *dv1, *dv2;

    if (self == other) return Qtrue;
    if (CLASS_OF(self) != CLASS_OF(other)) return Qfalse;

    Data_Get_Struct(self, RS_DVector, dv1);
    Data_Get_Struct(other, RS_DVector, dv2);
    if (dv1->len != dv2->len) return Qfalse;
    if (dv1->len == 0) return Qtrue;

    return rb_exec_recursive(recursive_equal, self, other);
}

static VALUE recursive_eql(VALUE self, VALUE other, int recur)
{
    long i;
    RS_DVector *dv1, *dv2;

    Data_Get_Struct(self, RS_DVector, dv1);
    Data_Get_Struct(other, RS_DVector, dv2);

    if (recur) return Qfalse;
    for (i=0; i < dv1->len; i++) {
        if (!rb_eql(dv1->ptr[i], dv2->ptr[i]))
            return Qfalse;
    }
    return Qtrue;
}

static VALUE dv_method_eql(VALUE self, VALUE other)
{
    RS_DVector *dv1, *dv2;

    if (self == other) return Qtrue;
    if (CLASS_OF(self) != CLASS_OF(other)) return Qfalse;

    Data_Get_Struct(self, RS_DVector, dv1);
    Data_Get_Struct(other, RS_DVector, dv2);
    if (dv1->len != dv2->len) return Qfalse;
    if (dv1->len == 0) return Qtrue;

    return rb_exec_recursive(recursive_eql, self, other);
}

static VALUE recursive_hash(VALUE self, VALUE dummy, int recur)
{
    long i, h;
    VALUE n;
    RS_DVector *dv;

    if (recur) {
	return LONG2FIX(0);
    }

    Data_Get_Struct(self, RS_DVector, dv);

    h = dv->len;
    for (i=0; i < dv->len; i++) {
	h = (h << 1) | (h<0 ? 1 : 0);
	n = rb_hash(dv->ptr[i]);
	h ^= NUM2LONG(n);
    }
    return LONG2FIX(h);
}

static VALUE dv_method_hash(VALUE self)
{
    return rb_exec_recursive(recursive_hash, self, 0);
}

static VALUE dv_method_dump_data(VALUE self)
{
    RS_DVector *dv;
    Data_Get_Struct(self, RS_DVector, dv);
    return dv->ptr ? rb_ary_new4(dv->len, dv->ptr) : rb_ary_new();
}

static VALUE dv_method_load_data(VALUE self, VALUE from_array)
{
    long i;
    RS_DVector *dv;
    Data_Get_Struct(self, RS_DVector, dv);

    for (i=0; i < RARRAY_LEN(from_array); i++) {
        rs_dv_push(dv, RARRAY_PTR(from_array)[i]);
    }
    
    return self;
}

VALUE rs_cDVector;

void
Init_dvector(void)
{
    rs_cDVector = rb_path2class("RedShift::DVector");

    rb_define_alloc_func(rs_cDVector, dv_alloc);
    rb_define_method(rs_cDVector, "push", dv_method_push, -1);
    rb_define_method(rs_cDVector, "pop", dv_method_pop, 0);

    rb_define_method(rs_cDVector, "each", dv_method_each, 0);
    rb_define_method(rs_cDVector, "to_a", dv_method_to_a, 0);
    rb_define_method(rs_cDVector, "length", dv_method_length, 0);
    rb_define_alias(rs_cDVector,  "size", "length");

    rb_define_method(rs_cDVector, "==", dv_method_equal, 1);
    rb_define_method(rs_cDVector, "eql?", dv_method_eql, 1);
    rb_define_method(rs_cDVector, "hash", dv_method_hash, 0);

    rb_define_method(rs_cDVector, "_load_data", dv_method_load_data, 1);
    rb_define_method(rs_cDVector, "_dump_data", dv_method_dump_data, 0);
}

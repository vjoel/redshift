#include "dvector-float.h"
#include <math.h>

static VALUE dvf_alloc(VALUE klass)
{
    VALUE self;
    RS_DVectorFloat *dvf;
    
    self = Data_Make_Struct(klass, RS_DVectorFloat, 0, -1, dvf);

    dvf->len = 0;
    dvf->capa = 0;
    dvf->ptr = 0;
    
    return self;
}

void rs_dvf_grow(RS_DVectorFloat *dvf)
{
    if (!dvf->ptr) {
        dvf->capa = 16;
        dvf->ptr = ALLOC_N(float, dvf->capa);
    }
    else if (dvf->len == dvf->capa) {
        dvf->capa *= 2;
        REALLOC_N(dvf->ptr, float, dvf->capa);
    }
}

void rs_dvf_shrink(RS_DVectorFloat *dvf)
{
    if (dvf->ptr && dvf->len < dvf->capa) {
        REALLOC_N(dvf->ptr, float, dvf->len);
        dvf->capa = dvf->len;
    }
}

static VALUE dvf_method_push(int argc, VALUE *argv, VALUE self)
{
    int i;
    RS_DVectorFloat *dvf;
    
    Data_Get_Struct(self, RS_DVectorFloat, dvf);
    
    for (i = 0; i < argc; i++) {
        rs_dvf_push(dvf, NUM2DBL(argv[i]));
    }

    return self;
}

static VALUE dvf_method_pop(VALUE self)
{
    RS_DVectorFloat *dvf;
    
    Data_Get_Struct(self, RS_DVectorFloat, dvf);

    return dvf->len == 0 ? Qnil : rb_float_new(rs_dvf_pop(dvf));
}

static VALUE dvf_method_each(VALUE self)
{
    long i;
    RS_DVectorFloat *dvf;
    
    Data_Get_Struct(self, RS_DVectorFloat, dvf);

    RETURN_ENUMERATOR(self, 0, 0);
    for (i=0; i < dvf->len; i++) {
	rb_yield(rb_float_new(dvf->ptr[i]));
    }
    
    return self;
}

static VALUE dvf_method_to_a(VALUE self)
{
    int i;
    RS_DVectorFloat *dvf;
    VALUE ary;
    
    Data_Get_Struct(self, RS_DVectorFloat, dvf);

    ary = rb_ary_new();
    if (!dvf->ptr) return ary;

    for (i=0; i < dvf->len; i++) {
	rb_ary_push(ary, rb_float_new(dvf->ptr[i]));
    }
    
    return ary;
}

static VALUE dvf_method_length(VALUE self)
{
    RS_DVectorFloat *dvf;
    Data_Get_Struct(self, RS_DVectorFloat, dvf);
    return INT2NUM(dvf->len);
}

static VALUE dvf_method_equal(VALUE self, VALUE other)
{
    int i;
    RS_DVectorFloat *dvf1, *dvf2;

    if (self == other) return Qtrue;
    if (CLASS_OF(self) != CLASS_OF(other)) return Qfalse;

    Data_Get_Struct(self, RS_DVectorFloat, dvf1);
    Data_Get_Struct(other, RS_DVectorFloat, dvf2);
    if (dvf1->len != dvf2->len) return Qfalse;

    for (i=0; i < dvf1->len; i++) {
        if (dvf1->ptr[i] != dvf2->ptr[i]) return Qfalse;
    }
    return Qtrue;
}

static VALUE dvf_method_hash(VALUE self)
{
    long i, h;
    RS_DVectorFloat *dvf;

    Data_Get_Struct(self, RS_DVectorFloat, dvf);

    h = dvf->len;
    for (i=0; i < dvf->len; i++) {
        int hash, j;
        char *c;
        float f;
        
	h = (h << 1) | (h<0 ? 1 : 0);
        f = dvf->ptr[i];

        if (f == 0) f = fabs(f);
        c = (char*)&f;
        for (hash=0, j=0; j<sizeof(float); j++) {
	    hash = (hash * 971) ^ (unsigned char)c[j];
        }
        if (hash < 0) hash = -hash;

	h ^= hash;
    }
    return LONG2FIX(h);
}

static VALUE dvf_method_load_data(VALUE self, VALUE from_array)
{
    long i;
    RS_DVectorFloat *dvf;
    Data_Get_Struct(self, RS_DVectorFloat, dvf);

    for (i=0; i < RARRAY_LEN(from_array); i++) {
        rs_dvf_push(dvf, NUM2DBL(RARRAY_PTR(from_array)[i]));
    }
    
    return self;
}

VALUE rs_cDVectorFloat;

void
Init_dvector_float(void)
{
    rs_cDVectorFloat = rb_path2class("RedShift::DVectorFloat");

    rb_define_alloc_func(rs_cDVectorFloat, dvf_alloc);
    rb_define_method(rs_cDVectorFloat, "push", dvf_method_push, -1);
    rb_define_method(rs_cDVectorFloat, "pop", dvf_method_pop, 0);
    rb_define_alias(rs_cDVectorFloat,  "<<", "push");

    rb_define_method(rs_cDVectorFloat, "each", dvf_method_each, 0);
    rb_define_method(rs_cDVectorFloat, "to_a", dvf_method_to_a, 0);
    rb_define_method(rs_cDVectorFloat, "length", dvf_method_length, 0);
    rb_define_alias(rs_cDVectorFloat,  "size", "length");

    rb_define_method(rs_cDVectorFloat, "==", dvf_method_equal, 1);
    rb_define_method(rs_cDVectorFloat, "eql?", dvf_method_equal, 1);
    rb_define_method(rs_cDVectorFloat, "hash", dvf_method_hash, 0);

    rb_define_method(rs_cDVectorFloat, "_load_data", dvf_method_load_data, 1);
    rb_define_method(rs_cDVectorFloat, "_dump_data", dvf_method_to_a, 0);
}

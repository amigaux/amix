/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi> */
#ifndef STUB_TYPES_H
#define STUB_TYPES_H
#include <stddef.h>
#include <stdarg.h>
typedef struct BIO_st BIO;
typedef struct X509_st X509;
typedef struct evp_md_st EVP_MD;
typedef struct evp_pkey_st EVP_PKEY;
typedef struct pkcs7_st PKCS7;
typedef struct pkcs12_st PKCS12;
typedef int pem_password_cb(char *buf, int size, int rwflag, void *userdata);
struct stack_st_X509;
struct stack_st_EVP_PKEY;
#define STACK_OF(type) struct stack_st_##type
#define DECLARE_STACK_OF(type)
#define SKM_sk_new_null(t) (NULL)
#define SKM_sk_free(t, st)
#define SKM_sk_num(t, st) (0)
#define SKM_sk_value(t, st, i) (NULL)
#define SKM_sk_push(t, st, v) (0)
#define SKM_sk_find(t, st, v) (-1)
#define SKM_sk_pop_free(t, st, f)
#define SKM_sk_dup(t, st) (NULL)
#endif

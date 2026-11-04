// Host stand-in for the parts of the Flipper Zero firmware API (furi.h) that the fuzzed apps touch.
#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNUSED(x) ((void)(x))

#define furi_check(cond, ...) \
    do {                      \
        if(!(cond)) abort();  \
    } while(0)
#define furi_assert(cond, ...) furi_check(cond)
#define FURI_LOG_E(tag, ...)   ((void)(tag))
#define FURI_LOG_W(tag, ...)   ((void)(tag))
#define FURI_LOG_I(tag, ...)   ((void)(tag))
#define FURI_LOG_D(tag, ...)   ((void)(tag))

static inline void furi_delay_us(uint32_t us) {
    (void)us;
}
static inline void furi_delay_ms(uint32_t ms) {
    (void)ms;
}

typedef struct FuriString FuriString;
FuriString* furi_string_alloc(void);
void furi_string_free(FuriString* s);
void furi_string_cat_printf(FuriString* s, const char* fmt, ...);
const char* furi_string_get_cstr(const FuriString* s);

#ifdef __cplusplus
}
#endif

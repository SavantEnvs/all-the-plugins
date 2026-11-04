// Fuzzes the calculator app's embedded tinyexpr parser/evaluator with arbitrary expression text.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "tinyexpr.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if(size == 0 || size > 4096) return -1;

    char* expr = malloc(size + 1);
    memcpy(expr, data, size);
    expr[size] = '\0';

    int err = 0;
    (void)te_interp(expr, &err);

    double x = 1.5, y = -2.0;
    te_variable vars[] = {{"x", &x, TE_VARIABLE, NULL}, {"y", &y, TE_VARIABLE, NULL}};
    te_expr* n = te_compile(expr, vars, 2, &err);
    if(n) {
        (void)te_eval(n);
        te_free(n);
    }

    free(expr);
    return 0;
}

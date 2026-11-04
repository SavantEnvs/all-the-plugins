// Known-answer probe for the C code under fuzz: prints one `name=value` line per check so
// mayhem/test.sh can compare against fixed expected values.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "furi_hal.h"
#include "tinyexpr.h"
#include "uhf_module.h"

static void expr(const char* e) {
    int err = 0;
    double v = te_interp(e, &err);
    printf("expr[%s]=%.6f err=%d\n", e, v, err);
}

static M100Module* new_module(void) {
    M100Module* m = calloc(1, sizeof(M100Module));
    m->info = m100_module_info_alloc();
    memset(m->info, 0, sizeof(*m->info));
    m->uart = uhf_uart_alloc();
    return m;
}

static void free_module(M100Module* m) {
    m100_module_info_free(m->info);
    uhf_uart_free(m->uart);
    free(m);
}

int main(void) {
    expr("2+3*4");
    expr("sqrt(16)+2^3");
    expr("-(1+2)*3");
    expr("5%3+10/4");
    expr("2+");

    const uint8_t hw_cmd[] = {0x00, 0x03, 0x00, 0x01, 0x00};
    printf("checksum=%02x\n", checksum(hw_cmd, sizeof(hw_cmd)));
    printf("crc16_genibus=%04x\n", crc16_genibus((const uint8_t*)"123456789", 9));

    static const uint8_t poll[] = {0xbb, 0x02, 0x22, 0x00, 0x11, 0xc7, 0x30, 0x00, 0xe2, 0x80,
                                   0x11, 0x60, 0x60, 0x00, 0x02, 0x05, 0x4a, 0x3b, 0x1c, 0x2d,
                                   0x3d, 0x47, 0xb8, 0x7e};
    M100Module* m = new_module();
    UHFTag* tag = uhf_tag_alloc();
    uhf_tag_reset(tag);
    mayhem_uart_set_response(poll, sizeof(poll));
    M100ResponseType r = m100_single_poll(m, tag);
    printf("poll=%d size=%zu pc=%04x crc=%04x epc=", (int)r, uhf_tag_get_epc_size(tag),
           uhf_tag_get_epc_pc(tag), uhf_tag_get_epc_crc(tag));
    for(size_t i = 0; i < uhf_tag_get_epc_size(tag); i++) printf("%02x", uhf_tag_get_epc(tag)[i]);
    printf("\n");

    uint8_t bad[sizeof(poll)];
    memcpy(bad, poll, sizeof(poll));
    bad[10] ^= 0xff;
    mayhem_uart_set_response(bad, sizeof(bad));
    printf("poll_corrupt=%d\n", (int)m100_single_poll(m, tag));
    mayhem_uart_set_response(poll, 0);
    printf("poll_empty=%d\n", (int)m100_single_poll(m, tag));
    uhf_tag_free(tag);
    free_module(m);

    static const uint8_t hw[] = {0xbb, 0x01, 0x03, 0x00, 0x08, 0x00, 0x4d, 0x31, 0x30, 0x30,
                                 0x76, 0x31, 0x2e, 0x30, 0xef, 0x7e};
    m = new_module();
    mayhem_uart_set_response(hw, sizeof(hw));
    char* v = m100_get_hardware_version(m);
    printf("hw=%.8s\n", v ? v : "(null)");
    free_module(m);
    return 0;
}

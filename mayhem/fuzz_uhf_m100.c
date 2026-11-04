// Fuzzes the UHF RFID app's M100 module driver: the fuzzer plays the module and answers a command
// with arbitrary bytes, which travel through the driver's real UART rx callback, ring buffer,
// frame validation and response parsers (poll, select, read/write storage, version strings).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "furi_hal.h"
#include "uhf_module.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if(size < 3 || size > 512) return -1;

    uint8_t op = data[0] % 8;
    size_t epc_size = data[1] % 64;
    const uint8_t* resp = data + 2;
    size_t resp_size = size - 2;

    static const uint8_t zeros[MAX_BANK_SIZE];
    uint8_t* response = malloc(resp_size);
    memcpy(response, resp, resp_size);
    mayhem_uart_set_response(response, resp_size);

    // m100_module_alloc() leaves the info string pointers uninitialised, so freeing the module
    // crashes on every input; build the same module with them zeroed to reach the parsers.
    M100Module* module = calloc(1, sizeof(M100Module));
    module->transmitting_power = DEFAULT_TRANSMITTING_POWER;
    module->region = DEFAULT_WORKING_REGION;
    module->info = m100_module_info_alloc();
    memset(module->info, 0, sizeof(*module->info));
    module->uart = uhf_uart_alloc();
    module->write_mask = WRITE_EPC;
    UHFTag* tag = uhf_tag_alloc();
    UHFTag* selected = uhf_tag_alloc();
    uhf_tag_reset(tag);
    uhf_tag_reset(selected);
    uhf_tag_set_epc(tag, (uint8_t*)zeros, epc_size);
    uhf_tag_set_epc(selected, (uint8_t*)zeros, epc_size);
    uhf_tag_set_user(tag, (uint8_t*)zeros, epc_size);

    switch(op) {
    case 0:
        m100_get_hardware_version(module);
        break;
    case 1:
        m100_get_software_version(module);
        break;
    case 2:
        m100_get_manufacturers(module);
        break;
    case 3:
        m100_single_poll(module, tag);
        break;
    case 4:
        m100_set_select(module, tag);
        break;
    case 5:
        m100_read_label_data_storage(module, tag, (BankType)(1 + (data[1] >> 6)), 0, 2);
        break;
    case 6:
        m100_write_label_data_storage(module, tag, selected, (BankType)(data[1] >> 6), 0, 0);
        break;
    default:
        m100_set_working_region(module, WR_US);
        m100_set_transmitting_power(module, 2000);
        break;
    }

    uhf_tag_free(tag);
    uhf_tag_free(selected);
    m100_module_info_free(module->info);
    uhf_uart_free(module->uart);
    free(module);
    free(response);
    mayhem_uart_set_response(NULL, 0);
    return 0;
}

// Host implementations of the furi / furi_hal symbols used by the M100 UHF RFID driver.
// A command written to the serial port is answered by replaying the harness-supplied bytes through
// the driver's own RX callback, exactly as the UART ISR would on the device.
#include "furi_hal.h"

struct FuriString {
    char* data;
    size_t len;
};

struct FuriHalSerialHandle {
    FuriHalSerialAsyncRxCallback callback;
    void* context;
    const uint8_t* response;
    size_t response_size;
    size_t cursor;
};

static struct FuriHalSerialHandle g_handle;

FuriString* furi_string_alloc(void) {
    FuriString* s = malloc(sizeof(*s));
    s->data = malloc(1);
    s->data[0] = '\0';
    s->len = 0;
    return s;
}

void furi_string_free(FuriString* s) {
    free(s->data);
    free(s);
}

void furi_string_cat_printf(FuriString* s, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char tmp[16];
    int n = vsnprintf(tmp, sizeof(tmp), fmt, args);
    va_end(args);
    if(n < 0) return;
    if((size_t)n >= sizeof(tmp)) n = sizeof(tmp) - 1;
    s->data = realloc(s->data, s->len + (size_t)n + 1);
    memcpy(s->data + s->len, tmp, (size_t)n);
    s->len += (size_t)n;
    s->data[s->len] = '\0';
}

const char* furi_string_get_cstr(const FuriString* s) {
    return s->data;
}

FuriHalSerialHandle* furi_hal_serial_control_acquire(FuriHalSerialId id) {
    (void)id;
    return &g_handle;
}
void furi_hal_serial_control_release(FuriHalSerialHandle* handle) {
    (void)handle;
}
void furi_hal_serial_init(FuriHalSerialHandle* handle, uint32_t baud) {
    (void)handle;
    (void)baud;
}
void furi_hal_serial_deinit(FuriHalSerialHandle* handle) {
    (void)handle;
}
void furi_hal_serial_set_br(FuriHalSerialHandle* handle, uint32_t baud) {
    (void)handle;
    (void)baud;
}
void furi_hal_serial_async_rx_start(
    FuriHalSerialHandle* handle,
    FuriHalSerialAsyncRxCallback callback,
    void* context,
    bool report_errors) {
    (void)report_errors;
    handle->callback = callback;
    handle->context = context;
}
void furi_hal_serial_async_rx_stop(FuriHalSerialHandle* handle) {
    handle->callback = NULL;
}

uint8_t furi_hal_serial_async_rx(FuriHalSerialHandle* handle) {
    return handle->response[handle->cursor++];
}

void mayhem_uart_set_response(const uint8_t* data, size_t size) {
    g_handle.response = data;
    g_handle.response_size = size;
    g_handle.cursor = 0;
}

void furi_hal_serial_tx(FuriHalSerialHandle* handle, const uint8_t* buffer, size_t buffer_size) {
    (void)buffer;
    (void)buffer_size;
    handle->cursor = 0;
    while(handle->callback && handle->cursor < handle->response_size) {
        handle->callback(handle, FuriHalSerialRxEventData, handle->context);
    }
}

void furi_hal_serial_tx_wait_complete(FuriHalSerialHandle* handle) {
    (void)handle;
}

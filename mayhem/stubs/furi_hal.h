// Host stand-in for furi_hal.h: the serial HAL used by the M100 UHF RFID module driver.
#pragma once

#include "furi.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    FuriHalBusUSART1,
} FuriHalBus;

typedef enum {
    FuriHalSerialIdUsart,
    FuriHalSerialIdLpuart,
} FuriHalSerialId;

typedef enum {
    FuriHalSerialRxEventData = (1 << 0),
} FuriHalSerialRxEvent;

typedef struct FuriHalSerialHandle FuriHalSerialHandle;
typedef void (*FuriHalSerialAsyncRxCallback)(
    FuriHalSerialHandle* handle,
    FuriHalSerialRxEvent event,
    void* context);

FuriHalSerialHandle* furi_hal_serial_control_acquire(FuriHalSerialId id);
void furi_hal_serial_control_release(FuriHalSerialHandle* handle);
void furi_hal_serial_init(FuriHalSerialHandle* handle, uint32_t baud);
void furi_hal_serial_deinit(FuriHalSerialHandle* handle);
void furi_hal_serial_set_br(FuriHalSerialHandle* handle, uint32_t baud);
void furi_hal_serial_async_rx_start(
    FuriHalSerialHandle* handle,
    FuriHalSerialAsyncRxCallback callback,
    void* context,
    bool report_errors);
void furi_hal_serial_async_rx_stop(FuriHalSerialHandle* handle);
uint8_t furi_hal_serial_async_rx(FuriHalSerialHandle* handle);
void furi_hal_serial_tx(FuriHalSerialHandle* handle, const uint8_t* buffer, size_t buffer_size);
void furi_hal_serial_tx_wait_complete(FuriHalSerialHandle* handle);

// Harness hook: the bytes the "reader module" answers with to the next command.
void mayhem_uart_set_response(const uint8_t* data, size_t size);

#ifdef __cplusplus
}
#endif

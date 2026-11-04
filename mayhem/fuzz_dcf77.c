// Fuzzes the flipper-dcf77 radio-clock frame encoders (DCF77/WWVB/BPC/JJY/MSF/RBU/HBG/BSF) with
// arbitrary calendar fields; the input is a signal selector plus a RadioClockProtocolTime.
#include <stdint.h>
#include <string.h>

#include "radio_clock_protocol.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if(size < 10) return -1;

    RadioClockSignal signal = (RadioClockSignal)(data[0] % RadioClockSignalCount);

    RadioClockProtocolTime t;
    memset(&t, 0, sizeof(t));
    t.year = (uint16_t)(data[1] | (data[2] << 8));
    // The app feeds these from the RTC, so keep them inside the calendar ranges the encoders assume.
    t.day_of_year = (uint16_t)(1 + (data[3] | (data[4] << 8)) % 366);
    t.month = (uint8_t)(1 + data[5] % 12);
    t.day = (uint8_t)(1 + data[6] % 31);
    t.weekday = (uint8_t)(data[7] % 7);
    t.hour = (uint8_t)(data[8] % 24);
    t.minute = (uint8_t)(data[9] % 60);

    static RadioClockMinuteFrame frame;
    memset(&frame, 0, sizeof(frame));
    radio_clock_protocol_prepare_frame(signal, &frame, &t);
    (void)radio_clock_protocol_day_of_year(t.year, t.month, t.day);
    (void)radio_clock_protocol_uses_following_minute(signal);
    for(unsigned i = 0; i < RADIO_CLOCK_FRAME_SECONDS; i++) {
        (void)radio_clock_protocol_pulse_label(frame.pulses[i]);
    }
    return 0;
}

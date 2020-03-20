#include "slipdev_icicle.h"
#include "slipdev.h"

#include <stdint.h>

#define UART_BAUD   *((volatile uint32_t *) 0x00020000)
#define UART_STATUS *((volatile uint32_t *) 0x00020004)
#define UART_DATA   *((volatile  int32_t *) 0x00020008)

#define UART_STATUS_TX_READY 0x1
#define UART_STATUS_RX_READY 0x2

#define BAUD_RATE 9600

void slipdev_icicle_init(void) {
    UART_BAUD = FREQ / BAUD_RATE;
    slipdev_init();
}

void slipdev_char_put(uint8_t c) {
    while (!(UART_STATUS & UART_STATUS_TX_READY));
    UART_DATA = c;
}

uint8_t slipdev_char_poll(uint8_t *c) {
    int32_t data = UART_DATA;
    if (data >= 0) {
        *c = data;
        return 1;
    } else {
        return 0;
    }
}

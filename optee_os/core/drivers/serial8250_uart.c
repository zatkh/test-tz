// SPDX-License-Identifier: BSD-2-Clause
/*
 * Copyright (c) 2015, Linaro Limited
 */

#include <compiler.h>
#include <console.h>
#include <drivers/serial8250_uart.h>
#include <io.h>
#include <keep.h>
#include <util.h>

/* uart register defines */
#define UART_RHR	0x0
#define UART_THR	0x0
#define UART_IER	0x4
#define UART_ISR	0x8
#define UART_FCR	0x8
#define UART_LCR	0xc
#define UART_MCR	0x10
#define UART_LSR	0x14
#define UART_MSR	0x18
#define UART_SPR	0x1c

/* uart status register bits */
#define LSR_TEMT	0x40 /* Transmitter empty */
#define LSR_THRE	0x20 /* Transmit-hold-register empty */
#define LSR_EMPTY	(LSR_TEMT | LSR_THRE)
#define LSR_DR		0x01 /* DATA Ready */

static vaddr_t chip_to_base(struct serial_chip *chip)
{
	struct serial8250_uart_data *pd =
		container_of(chip, struct serial8250_uart_data, chip);

	return io_pa_or_va(&pd->base);
}

static void serial8250_uart_flush(struct serial_chip *chip)
{
	vaddr_t base = chip_to_base(chip);

	while (1) {
		uint32_t state = read32(base + UART_LSR);

		/* Wait until transmit FIFO is empty */
		if ((state & LSR_EMPTY) == LSR_EMPTY)
			break;
	}
}

static bool serial8250_uart_have_rx_data(struct serial_chip *chip)
{
	vaddr_t base = chip_to_base(chip);

	return (read32(base + UART_LSR) & LSR_DR);
}

static int serial8250_uart_getchar(struct serial_chip *chip)
{
	vaddr_t base = chip_to_base(chip);

	while (!serial8250_uart_have_rx_data(chip)) {
		/* Transmit FIFO is empty, waiting again */
		;
	}
	return read32(base + UART_RHR) & 0xff;
}

static void serial8250_uart_putc(struct serial_chip *chip, int ch)
{
	vaddr_t base = chip_to_base(chip);

	serial8250_uart_flush(chip);

	/* Write out character to transmit FIFO */
	write32(ch, base + UART_THR);
}

static const struct serial_ops serial8250_uart_ops = {
	.flush = serial8250_uart_flush,
	.getchar = serial8250_uart_getchar,
	.have_rx_data = serial8250_uart_have_rx_data,
	.putc = serial8250_uart_putc,
};
KEEP_PAGER(serial8250_uart_ops);

void serial8250_uart_init(struct serial8250_uart_data *pd, paddr_t base,
			  uint32_t __unused uart_clk,
			  uint32_t __unused baud_rate)

{
	pd->base.pa = base;
	pd->chip.ops = &serial8250_uart_ops;

	/*
	 * do nothing, debug uart(uart0) share with normal world,
	 * everything for uart0 is ready now.
	 */
}

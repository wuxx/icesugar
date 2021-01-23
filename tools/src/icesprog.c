/*
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/* author: wuxx */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include <hidapi.h>
#include <libusb.h>

#include <getopt.h>

#ifndef O_BINARY
#define O_BINARY 0
#endif

#define readb(addr)         (*( ( volatile uint8_t * )(addr)) )
#define writeb(addr, data)  (*( ( volatile uint8_t * )(addr)) = data)

#define reads(addr)         (*( ( volatile uint16_t * )(addr)) )
#define writes(addr, data)  (*( ( volatile uint16_t * )(addr)) = data)

#define readl(addr)         (*( ( volatile uint32_t * )(addr)) )
#define writel(addr, data)  (*( ( volatile uint32_t * )(addr)) = data)

#define ICELINK_VID (0x1d50)
#define ICELINK_PID (0x602b)

#define PACKET_SIZE       (64 + 1)  /* 64 bytes plus report id */
#define USB_TIMEOUT_DEFAULT 1000

#define ID_DAP_Vendor0  0x80U
#define ID_DAP_Vendor13 0x8DU

#define SPI_FLASH_SIZE          flash_size
#define SPI_FLASH_SECTOR_SIZE   (4096)
#define SPI_FLASH_SECTOR_ALIGN_UP(x)     ((x + SPI_FLASH_SECTOR_SIZE - 1) & (~(SPI_FLASH_SECTOR_SIZE - 1)))
#define SPI_FLASH_SECTOR_ALIGN_DOWN(x)   ((x) & (~(SPI_FLASH_SECTOR_SIZE - 1)))

enum BOARD_TYPE_E {
    BT_iCESugar      = 0,           /* iCE40UP5K */
    BT_iCESugar_Pro  = 0xa55a0001,  /* ECP5 LFE5U-25F-BG256 */
    BT_iCESugar_Nano = 0xa55a0002,  /* iCE40LP1K */
    BT_Unknown       = 0xFFFFFFFF,
};

enum ICELINK_CMD_E {
    CMD_FLASH_GET_INFO = 0,
    CMD_FLASH_TRANSACTION_START,
    CMD_FLASH_TRANSACTION_END,
    CMD_RAM_WRITE,
    CMD_RAM_READ,
    CMD_FLASH_WRITE_SECTOR,
    CMD_FLASH_READ_SECTOR,
    CMD_FLASH_ERASE_CHIP,

    CMD_SYS_GET_INFO = 0x80,
    CMD_SYS_GPIO_MODE,
    CMD_SYS_GPIO_WRITE,
    CMD_SYS_GPIO_READ,
    CMD_SYS_JTAG_SEL,
    CMD_SYS_JTAG_INFO,
    CMD_SYS_MCO_SEL,
    CMD_SYS_MCO_INFO,
};

enum MCO_SOURCE_E {
    MCO_HSI = 1, /*  8MHz */
    MCO_HSE,     /* 12MHz */
    MCO_PLLCLK,  /* 36MHz */ /* actually is RCC_CFGR_MCO_PLLCLK_DIV2 */
    MCO_SYSCLK,  /* 72MHz */
    MCO_MAX,
};

struct icelink {
    hid_device *dev_handle;
    uint8_t packet_buffer[PACKET_SIZE];
	uint32_t packet_size;
};

static struct icelink icelink_handle;

struct icelink_packet_head {
    uint8_t vendor_cmd;
    uint8_t icelink_cmd;
    uint8_t data[0];
};

int32_t board_type = BT_Unknown;

uint32_t flash_id = 0;
uint32_t flash_size = 8 * 1024 * 1024;

static uint8_t cook(uint8_t c)
{
    /* please check the ascii code table */
    if (c >= 0x20 && c <= 0x7E) {
        return c;
    } else {
        return '.';
    }
}

void dumpb(uint8_t *p, uint32_t byte_nr)
{
    uint32_t i = 0, x;
    uint8_t buf[16];
    uint32_t count, left;

    count = byte_nr / 16;
    left  = byte_nr % 16;

    fprintf(stdout,"[0x%08x]: ", i);
    for(i = 0; i < count; i++) {
        for(x = 0; x < 16; x++) {
            buf[x] = p[i * 16 + x];
            fprintf(stdout,"%02x ", buf[x]);
        }
        fprintf(stdout,"  ");
        for(x = 0; x < 16; x++) {
            fprintf(stdout,"%c", cook(buf[x]));
        }

        fprintf(stdout,"\n[0x%08x]: ", (i + 1) * 16);
    }

    if (left != 0) {
        for(x = 0; x < 16; x++) {
            if (x < left) {
                buf[x] = p[i * 16 + x];
                fprintf(stdout,"%02x ", buf[x]);
            } else {
                buf[x] = ' ';
                fprintf(stdout,"   ");
            }
        }
        fprintf(stdout,"  ");
        for(x = 0; x < 16; x++) {
            fprintf(stdout,"%c", cook(buf[x]));
        }

    }

    fprintf(stdout,"\n");

}

int icelink_usb_xfer(int txlen)
{
    int32_t retval;

    /* Pad the rest of the TX buffer with 0's */
    memset(icelink_handle.packet_buffer + txlen, 0, icelink_handle.packet_size - txlen);

    /* write data to device */
    retval = hid_write(icelink_handle.dev_handle,
            icelink_handle.packet_buffer, icelink_handle.packet_size);
    if (retval == -1) {
        fprintf(stderr, "error writing data: %ls", hid_error(icelink_handle.dev_handle));
        return -1;
    }

    /* get reply */
    retval = hid_read_timeout(icelink_handle.dev_handle, icelink_handle.packet_buffer,
            icelink_handle.packet_size, USB_TIMEOUT_DEFAULT);
    if (retval == -1 || retval == 0) {
        fprintf(stderr, "error reading data: %ls", hid_error(icelink_handle.dev_handle));
        return -1;
    }

    return 0;
}

int icelink_usb_xfer_wait(int txlen)
{
    int32_t retval;

    /* Pad the rest of the TX buffer with 0's */
    memset(icelink_handle.packet_buffer + txlen, 0, icelink_handle.packet_size - txlen);

    /* write data to device */
    retval = hid_write(icelink_handle.dev_handle,
            icelink_handle.packet_buffer, icelink_handle.packet_size);
    if (retval == -1) {
        fprintf(stderr, "error writing data: %ls", hid_error(icelink_handle.dev_handle));
        return -1;
    }

    /* get reply */
    retval = hid_read_timeout(icelink_handle.dev_handle, icelink_handle.packet_buffer,
            icelink_handle.packet_size, -1);
    if (retval == -1 || retval == 0) {
        fprintf(stderr, "error reading data: %ls", hid_error(icelink_handle.dev_handle));
        return -1;
    }

    return 0;
}

int icelink_flash_get_info(int verbose)
{
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_FLASH_GET_INFO;

    if (icelink_usb_xfer_wait(3) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_GET_INFO failed.");
        return -1;
    }

    flash_id = *((uint32_t *)(&(icelink_handle.packet_buffer[2])));

    if (verbose) { fprintf(stdout, "flash id: 0x%x ", flash_id); }
    switch (flash_id) {
        case (0xEF4015):
            if (verbose) { fprintf(stdout, "w25q16 (4MB)\n"); }
            flash_size = 4 * 1024 * 1024;
            break;
        case (0xEF4017):
            if (verbose) { fprintf(stdout, "w25q64 (8MB)\n"); }
            flash_size = 8 * 1024 * 1024;
            break;
        case (0xEF4018):
            if (verbose) { fprintf(stdout, "w25q128 (16MB)\n"); }
            flash_size = 16 * 1024 * 1024;
            break;
        case (0xEF4019):
            if (verbose) { fprintf(stdout, "w25q256 (32MB)\n"); }
            flash_size = 32 * 1024 * 1024;
            break;
        default:
            if (verbose) { fprintf(stdout, "unknown (??MB)\n"); }
            break;
    }

    return flash_id;
}

int icelink_flash_transaction_start()
{
    struct icelink_packet_head *ph;
    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_FLASH_TRANSACTION_START;

    if (icelink_usb_xfer(3) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_TRANSACTION_START failed.");
        exit(-1);
    }

    return 0;
}

int icelink_flash_transaction_end()
{
    struct icelink_packet_head *ph;
    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_FLASH_TRANSACTION_END;

    if (icelink_usb_xfer(3) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_TRANSACTION_END failed.\n");
        exit(-1);
    }

    return 0;
}

/* max read count: 65 - 7 = 58 */
int icelink_ram_read(uint16_t ram_addr, uint8_t *buf, uint16_t count)
{
    struct icelink_packet_head *ph;
    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_RAM_READ;
    writes(&ph->data[0], ram_addr);
    writes(&ph->data[2], count);

    //dumpb(icelink_handle.packet_buffer, 16);

    if (icelink_usb_xfer(7) != 0) {
        fprintf(stderr, "iCELink CMD_RAM_READ failed.\n");
        return -1;
    }

    memcpy(buf, &(icelink_handle.packet_buffer[2]), count);

    return 0;
}

#define RAM_RW_SIZE   (58)

int icelink_ram_read_sector(uint8_t *buf)
{
    uint32_t i, offset = 0;
    uint32_t count, left_size;
    count     = SPI_FLASH_SECTOR_SIZE / RAM_RW_SIZE;
    left_size = SPI_FLASH_SECTOR_SIZE % RAM_RW_SIZE;

    for(i = 0; i < count; i++) {
	    if (icelink_ram_read(offset, &buf[offset], RAM_RW_SIZE) != 0) {
            fprintf(stderr, " icelink_ram_read 0x%x failed.\n", offset);
        }

        offset += RAM_RW_SIZE;
    }

    /* left */
    if (icelink_ram_read(offset, &buf[offset], left_size) != 0) {
        fprintf(stderr, " icelink_ram_read 0x%x failed.\n", left_size);
    }

    return 0;
}

int icelink_ram_dump()
{
	char flash_sector_ram[SPI_FLASH_SECTOR_SIZE] = {0};
    uint32_t roffset;

    for(roffset = 0; roffset < SPI_FLASH_SECTOR_SIZE; roffset += 32) {
	    if (icelink_ram_read(roffset, &flash_sector_ram[roffset], 32) != 0) {
            fprintf(stderr, " icelink_ram_read 0x%x failed.\n", roffset);
        }

    }

    dumpb(flash_sector_ram, SPI_FLASH_SECTOR_SIZE);

    return 0;
}

/* max write count: 65 - 7 = 58 */
int icelink_ram_write(uint16_t ram_addr, uint8_t *buf, uint16_t count)
{
    struct icelink_packet_head *ph;
    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_RAM_WRITE;
    writes(&ph->data[0], ram_addr);
    writes(&ph->data[2], count);

    memcpy(&ph->data[4], buf, count);

    if (icelink_usb_xfer(7 + count) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_TRANSACTION_END failed.\n");
        return -1;
    }

    return 0;
}

int icelink_ram_write_sector(uint8_t *buf)
{
    uint32_t raddr;

    uint32_t i, count, left_size;

    count     = SPI_FLASH_SECTOR_SIZE / RAM_RW_SIZE;
    left_size = SPI_FLASH_SECTOR_SIZE % RAM_RW_SIZE;
    raddr     = 0;

    for(i = 0; i < count; i++) {
	    if (icelink_ram_write(raddr, &buf[raddr], RAM_RW_SIZE) != 0) {
            fprintf(stderr, " icelink_ram_write 0x%x failed.\n", raddr);
        }
        raddr += RAM_RW_SIZE;
    }

    /* left */
    if (icelink_ram_write(raddr, &buf[raddr], left_size) != 0) {
        fprintf(stderr, " icelink_ram_write 0x%x failed.\n", raddr);
    }

    return 0;
}

/* read flash to ram */
int icelink_flash_read_sector(uint32_t flash_addr, uint8_t *buf)
{
    struct icelink_packet_head *ph;
    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_FLASH_READ_SECTOR;
    writel(&ph->data[0], flash_addr);

    if (icelink_usb_xfer(7) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_READ_SECTOR failed.\n");
        return -1;
    }

    icelink_ram_read_sector(buf);

    return 0;
}

int icelink_flash_read_sectors(uint32_t flash_addr, uint32_t sector_num, uint8_t *buf)
{
    uint32_t i, faddr;

    icelink_flash_transaction_start();

    for(i = 0; i < sector_num; i++) {
        faddr = flash_addr + i * SPI_FLASH_SECTOR_SIZE;
        if ((faddr & 0xffff) == 0) { fprintf(stdout, "read 0x%08x\r\n", faddr); }
        icelink_flash_read_sector(faddr, &buf[i * SPI_FLASH_SECTOR_SIZE]);
    }

    icelink_flash_transaction_end();

    return 0;
}

int icelink_flash_dump_sector(uint32_t flash_addr)
{
    uint8_t flash_sector[SPI_FLASH_SECTOR_SIZE];

    icelink_flash_transaction_start();

    icelink_flash_read_sector(flash_addr, flash_sector);

    icelink_flash_transaction_end();

    dumpb(flash_sector, SPI_FLASH_SECTOR_SIZE);

    return 0;
}

int icelink_flash_write_sector(uint32_t flash_addr, uint8_t *buf)
{
    struct icelink_packet_head *ph;

    icelink_ram_write_sector(buf);

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_FLASH_WRITE_SECTOR;
    writel(&ph->data[0], flash_addr);

    if (icelink_usb_xfer(7) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_READ_SECTOR failed.\n");
        return -1;
    }
    return 0;
}

int icelink_flash_write_sectors(uint32_t flash_addr, uint32_t sector_num, uint8_t *buf)
{
    uint32_t i, faddr;

    icelink_flash_transaction_start();

    for(i = 0; i < sector_num; i++) {
        faddr = flash_addr + i * SPI_FLASH_SECTOR_SIZE;
        if ((faddr & 0xffff) == 0) { fprintf(stdout, "write 0x%08x\r\n", faddr); }
        icelink_flash_write_sector(faddr, &buf[i * SPI_FLASH_SECTOR_SIZE]);
    }

    icelink_flash_transaction_end();

    return 0;
}

int icelink_flash_erase_chip()
{
    struct icelink_packet_head *ph;

    icelink_flash_transaction_start();

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_FLASH_ERASE_CHIP;

    if (icelink_usb_xfer_wait(3) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_ERASE_CHIP failed.\n");
        return -1;
    }

    icelink_flash_transaction_end();

    return 0;
}

int32_t icelink_sys_get_info()
{
    int32_t sys_info;
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_SYS_GET_INFO;

    if (icelink_usb_xfer_wait(3) != 0) {
        fprintf(stderr, "iCELink CMD_SYS_GET_INFO failed.\n");
        return -1;
    }

    sys_info = *((int32_t *)(&(icelink_handle.packet_buffer[2])));

    return sys_info;

}

int32_t icelink_sys_get_id(char *id)
{
    int i;
    struct icelink_packet_head *ph;
    uint8_t *pb;
    uint32_t size;

    pb = (uint8_t *)&icelink_handle.packet_buffer[1];

    //pb[0] = ID_DAP_Vendor0;

    pb[0] = 0x00; /* ID_DAP_Info */
    pb[1] = 0x03; /* DAP_ID_SER_NUM */

    if (icelink_usb_xfer(3) != 0) {
        fprintf(stderr, "iCELink ID_DAP_Vendor0 failed.\n");
        return -1;
    }

    pb = &(icelink_handle.packet_buffer[0]);
    size = pb[1];
#if 0
    for(i = 0; i < 8; i++) {
        fprintf(stdout, "pb[%d]: 0x%x\n", i, pb[i]);
    }
#endif

    memcpy(id, &pb[2], size);

    return 0;

}

int icelink_gpio_mode(uint32_t gpio_port, uint32_t gpio_index, uint32_t gpio_mode)
{
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_SYS_GPIO_MODE;

    writel(&(ph->data[0]), gpio_port);
    writel(&(ph->data[4]), gpio_index);
    writel(&(ph->data[8]), gpio_mode);

    if (icelink_usb_xfer_wait(15) != 0) {
        fprintf(stderr, "iCELink CMD_SYS_GPIO_MODE failed.\n");
        return -1;
    }

    return 0;
}


int32_t icelink_gpio_read(uint32_t gpio_port, uint32_t gpio_index)
{
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_SYS_GPIO_READ;

    writel(&(ph->data[0]), gpio_port);
    writel(&(ph->data[4]), gpio_index);

    if (icelink_usb_xfer_wait(11) != 0) {
        fprintf(stderr, "iCELink CMD_SYS_GPIO_MODE failed.\n");
        return -1;
    }

    return readl(&(icelink_handle.packet_buffer[2]));

}

int32_t icelink_gpio_write(uint32_t gpio_port, uint32_t gpio_index, uint32_t gpio_value)
{
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_SYS_GPIO_WRITE;

    writel(&(ph->data[0]), gpio_port);
    writel(&(ph->data[4]), gpio_index);
    writel(&(ph->data[8]), gpio_value);

    if (icelink_usb_xfer_wait(15) != 0) {
        fprintf(stderr, "iCELink CMD_SYS_GPIO_WRITE failed.\n");
        return -1;
    }

    return 0;

}

int32_t icelink_jtag_info()
{
    uint32_t jtag_num;

    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_SYS_JTAG_INFO;

    if (icelink_usb_xfer_wait(3) != 0) {
        fprintf(stderr, "iCELink CMD_SYS_JTAG_INFO failed.\n");
        return -1;
    }

    jtag_num = *((uint32_t *)(&(icelink_handle.packet_buffer[2])));

    return jtag_num;
}

int32_t icelink_jtag_select(int jtag_num)
{
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    if (board_type == BT_iCESugar_Pro) {

        ph->vendor_cmd  = ID_DAP_Vendor13;
        ph->icelink_cmd = CMD_SYS_JTAG_SEL;

        writel(&(ph->data[0]), jtag_num);

        if (icelink_usb_xfer_wait(7) != 0) {
            fprintf(stderr, "iCELink CMD_SYS_JTAG_SEL failed.\n");
            return -1;
        }

        jtag_num = icelink_jtag_info();
        fprintf(stdout, "JTAG --> [JTAG-%d]\n", jtag_num);
        fputs (("\
                    [JTAG-1]                                                \n\
                    TCK:  iCELink-PB6  -- ECP5-JTAG-TCK (25F-BG256-T10) \n\
                    TMS:  iCELink-PB4  -- ECP5-JTAG-TMS (25F-BG256-T11) \n\
                    TDI:  iCELink-PB5  -- ECP5-JTAG-TDI (25F-BG256-R11) \n\
                    TDO:  iCELink-PB3  -- ECP5-JTAG-TDO (25F-BG256-M10) \n\
                    \n\
                    [JTAG-2]                                                \n\
                    TCK:  iCELink-PA14 -- ECP5-IO-PL8D  (25F-BG256-F5)  \n\
                    TMS:  iCELink-PA13 -- ECP5-IO-PL17A (25F-BG256-H5)  \n\
                    TDI:  iCELink-PA0  -- ECP5-IO-PL38A (25F-BG256-N4)  \n\
                    TDO:  iCELink-PA1  -- ECP5-IO-PL17D (25F-BG256-J5)  \n\n\
                    "), stdout);

    } else {
        fprintf(stdout, "only iCESugar-Pro support jtag select\r\n");
    }

    return 0;
}

int32_t icelink_mco_info()
{
    int i;
    uint32_t mco_source;

    struct icelink_packet_head *ph;
    char *clk_desc[] = {"dummy", " 8MHz", "12MHz", "36MHz", "72MHz"};

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_SYS_MCO_INFO;

    if (icelink_usb_xfer_wait(3) != 0) {
        fprintf(stderr, "iCELink CMD_SYS_JTAG_INFO failed.\n");
        return -1;
    }

    mco_source = *((uint32_t *)(&(icelink_handle.packet_buffer[2])));


    fprintf(stdout, "CLK -> [%s]\n", clk_desc[mco_source]);
    fprintf(stdout, "CLK-SELECT:\n");
    for(i = 1; i < MCO_MAX; i++) {
        fprintf(stdout, "\t[%d]: %s\n", i, clk_desc[i]);
    }


    return mco_source;
}

int32_t icelink_mco_select(int mco_source)
{
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    if (board_type == BT_iCESugar_Nano) {

        ph->vendor_cmd  = ID_DAP_Vendor13;
        ph->icelink_cmd = CMD_SYS_MCO_SEL;

        writel(&(ph->data[0]), mco_source);

        if (icelink_usb_xfer_wait(7) != 0) {
            fprintf(stderr, "iCELink CMD_SYS_MCO_SEL failed.\n");
            return -1;
        }

    } else {
        fprintf(stdout, "only iCESugar-Nano support mco select\r\n");
    }

    return 0;
}

int32_t icelink_sys_get_board_type()
{
    char board_id[128] = {0};

    icelink_sys_get_id(board_id);

    //fprintf(stdout, "board_id: %s\n", board_id);

    if (strncmp(board_id, "0700", 4) == 0) {
        board_type = BT_iCESugar;
    } else if (strncmp(board_id, "0710", 4) == 0) {
        board_type = BT_iCESugar_Pro;
    } else if (strncmp(board_id, "0720", 4) == 0) {
        board_type = BT_iCESugar_Nano;
    } else {
        board_type = BT_Unknown;
    }

    return board_type;
}

int32_t icelink_dump_board_info(uint32_t board_type, uint32_t flash_id)
{

    switch (board_type) {
        case (BT_iCESugar):
            fprintf(stdout, "board: [iCESugar]\n");
            break;
        case (BT_iCESugar_Pro):
            fprintf(stdout, "board: [iCESugar-Pro]\n");
            break;
        case (BT_iCESugar_Nano):
            fprintf(stdout, "board: [iCESugar-Nano]\n");
            break;
        default:
            fprintf(stdout, "board: [Unknown]\n");
            break;
    }

    //fprintf(stdout, "flash id: 0x%x ", flash_id);
    switch (flash_id) {
        case (0xEF4015):
            fprintf(stdout, "flash: [w25q16] (2MB)\n");
            flash_size = 2 * 1024 * 1024;
            break;
        case (0xEF4017):
            fprintf(stdout, "flash: [w25q64] (8MB)\n");
            flash_size = 8 * 1024 * 1024;
            break;
        case (0xEF4018):
            fprintf(stdout, "flash: [w25q128] (16MB)\n");
            flash_size = 16 * 1024 * 1024;
            break;
        case (0xEF4019):
            fprintf(stdout, "flash: [w25q256] (32MB)\n");
            flash_size = 32 * 1024 * 1024;
            break;
        default:
            fprintf(stdout, "flash: unknown flash id 0x%x (??MB)\n", flash_id);
            break;
    }

}

void icelink_close()
{
    hid_close(icelink_handle.dev_handle);
    hid_exit();
}

int icelink_open()
{
    hid_device *dev = NULL;
    int i;
    struct hid_device_info *devs, *cur_dev;
    unsigned short target_vid, target_pid;
    wchar_t *target_serial = NULL;

    if (hid_init() != 0) {
        fprintf(stderr, "hid_init fail!\n");
        exit(-1);
    }

    if ((dev = hid_open(ICELINK_VID, ICELINK_PID, NULL)) == NULL) {
        fprintf(stderr, "iCELink open fail!\n");
        exit(-1);
    }

    icelink_handle.dev_handle  = dev;
	icelink_handle.packet_size = PACKET_SIZE;
    icelink_handle.packet_buffer[0] = 0; /* report number */

    return 0;
}

void usage(char *program_name)
{
    printf("usage: %s [OPTION] [FILE]\n", program_name);
    fputs (("\
             -w | --write                   write spi-flash or gpio                      \n\
             -r | --read                    read  spi-flash or gpio                      \n\
             -e | --erase                   erase spi-flash                              \n\
             -p | --probe                   probe spi-flash                              \n\
             -o | --offset                  spi-flash offset                  			 \n\
             -l | --len                     len of write/read                            \n\
             -g | --gpio                    icelink gpio write/read                      \n\
             -m | --mode                    icelink gpio mode                            \n\
             -j | --jtag-sel                jtag interface select (1 or 2)               \n\
             -c | --clk-sel                 clk source select (1 to 4)                   \n\
             -h | --help                    display help info                            \n\n\
             -- version 1.1b --\n\
"), stdout);
    exit(0);
}

static struct option const long_options[] =
{
  {"write",    no_argument,        NULL, 'w'},
  {"read",     no_argument,        NULL, 'r'},
  {"erase",    no_argument,        NULL, 'e'},
  {"probe",    no_argument,        NULL, 'p'},
  {"offset",   required_argument,  NULL, 'o'},
  {"len",      required_argument,  NULL, 'l'},

  /* gpio */
  {"gpio",     required_argument,  NULL, 'g'},
  {"mode",     required_argument,  NULL, 'm'},

  /* jtag select */
  {"jtag-sel", required_argument,  NULL, 'j'},

  /* clk select */
  {"clk-sel",  required_argument,  NULL, 'c'},

  {"help",     no_argument,        NULL, 'h'},
  {NULL,       0,                  NULL,  0 },
};

/* stm32f1xx_hal_gpio.h */
uint32_t gpio_mode_map(char *s)
{
    if (strcmp(s, "in") == 0) {
        return 0; /* GPIO_MODE_INPUT */
    } else if (strcmp(s, "out") == 0) {
        return 1; /* GPIO_MODE_OUTPUT_PP */
    } else {
        fprintf(stderr, "invalid gpio mode %s\n", s);
        exit(-1);
    }
}

int main(int argc, char **argv)
{
    char *ifile = NULL;

    char *flash_buf = NULL;

    int32_t c;
    int32_t option_index;
    int32_t fd;

    struct stat st;

    uint32_t len    = 0;
    uint32_t flash_offset = 0, sector_num = 0;

    uint32_t gpio_port = 0, gpio_index, gpio_value; 
    int32_t  gpio_mode = -1;

    int jtag_sel = -1;
    int mco_sel  = -1;

    int op_mode = 1; /* read: 0; write: 1; erase all: 2 */

    if (argc == 1) {
        usage(argv[0]);
        exit(-1);
    }

    while ((c = getopt_long (argc, argv, "wrpel:o:g:m:j:c:h",
                long_options, &option_index)) != -1) {
        switch (c) {
            case ('r'):
                op_mode = 0;
                break;
            case ('w'):
                op_mode = 1;
                break;
            case ('e'):
                op_mode = 2;
                break;
            case ('p'):
                op_mode = 3;
                break;
            case ('l'):
                len = strtoul(optarg, NULL, 0);
                break;
            case ('o'):
                flash_offset = strtoul(optarg, NULL, 0);
                break;
            case ('g'):
                //gpio_num = strtoul(&optarg[1], NULL, 16);
                gpio_port  = 0xA + (optarg[1] - 'A');
                gpio_index = strtoul(&optarg[2], NULL, 0);
                break;
            case ('m'):
                gpio_mode = gpio_mode_map(optarg);
                break;
            case ('j'):
                jtag_sel = strtoul(optarg, NULL, 0);
                break;
            case ('c'):
                mco_sel = strtoul(optarg, NULL, 0);
                break;
            case ('h'):
                usage(argv[0]);
                exit(0);
            default:
                usage(argv[0]);
                exit(0);
        }
    }

    ifile = argv[argc - 1];

    //printf("ifile: %s\r\n", ifile);
    flash_offset = SPI_FLASH_SECTOR_ALIGN_DOWN(flash_offset);


    icelink_open();

    //icelink_flash_get_info();
    //icelink_flash_dump_sector(0);

    if (jtag_sel != -1) {
        /* jtag select */
        if (jtag_sel == 1 || jtag_sel == 2) {
            icelink_sys_get_board_type();
            icelink_jtag_select(jtag_sel);
        } else {
            fprintf(stderr, "invalid jtag_num [%d] (should be 1 or 2)\r\n", jtag_sel);
            exit(-1);
        }

    } else if (mco_sel != -1) {
        icelink_sys_get_board_type();
        if (mco_sel == 0 || (mco_sel >= MCO_MAX)) {
            //fprintf(stdout, "mco_info:\n");
            icelink_mco_info();
        } else {
            icelink_mco_select(mco_sel);
            icelink_mco_info();
        }

    } else if (gpio_port != 0) {
        /* gpio control */
        //fprintf(stdout, "gpio_port  P%X\r\n", gpio_port);
        //fprintf(stdout, "gpio_index %d\r\n", gpio_index);
        if ((gpio_port >= 0xA && gpio_port <=0xF) && (gpio_index >= 0 && gpio_index <= 15)) {
            if (gpio_mode != -1) { /* gpio mode */
                fprintf(stdout, "gpio mode P%X%d 0x%x\r\n", gpio_port, gpio_index, gpio_mode);
                icelink_gpio_mode(gpio_port, gpio_index, gpio_mode);
            } else if (op_mode == 0) { /* gpio read */
                gpio_value = icelink_gpio_read(gpio_port, gpio_index);
                fprintf(stdout, "gpio read P%X%d return %d\r\n", gpio_port, gpio_index, gpio_value);
            } else if (op_mode == 1) { /* gpio write */
                gpio_value = strtoul(argv[argc - 1], NULL, 0);
                fprintf(stdout, "gpio write P%X%d %d\r\n", gpio_port, gpio_index, gpio_value);
                icelink_gpio_write(gpio_port, gpio_index, gpio_value);
            }

        } else {
            fprintf(stderr, "invalid gpio_num %X%d\r\n", gpio_port, gpio_index);
            exit(-1);
        }

    } else {
        /* flash access */
        if (op_mode == 0) {    /* read spi-flash */
            fprintf(stdout, "flash offset: 0x%08x\r\n", flash_offset);
            fprintf(stdout, "read flash (%d (0x%x) Bytes)\r\n", len, len);
            if (len == 0) {
                fprintf(stderr, "use -l to set read len\r\n");
                exit(-1);
            }

            //icelink_flash_get_info();

            if ((flash_offset + len) > SPI_FLASH_SIZE) {
                fprintf(stderr, "invalid read region [0x%08x, 0x%08x]\r\n", flash_offset, flash_offset + len);
                exit(-1);
            }

            if ((flash_buf = malloc(SPI_FLASH_SECTOR_ALIGN_UP(len))) == NULL) {
                perror("malloc");
                exit(-1);
            }

            memset(flash_buf, 0, SPI_FLASH_SECTOR_ALIGN_UP(len));

            sector_num = SPI_FLASH_SECTOR_ALIGN_UP(len) / SPI_FLASH_SECTOR_SIZE;

            icelink_flash_read_sectors(flash_offset, sector_num, flash_buf);

            if ((fd = open(ifile, O_CREAT | O_RDWR | O_TRUNC | O_BINARY, 0664)) == -1) {
                perror("open");
                exit(-1);
            }

            if (write(fd, flash_buf, len) != len) {
                perror("write");
                exit(-1);
            }

            close(fd);

        } else if (op_mode == 1) { /* write spi-flash */
            fprintf(stdout, "flash offset: 0x%08x\r\n", flash_offset);
            if ((fd = open(ifile, O_RDONLY | O_BINARY)) == -1) {
                perror("open");
                exit(-1);
            }

            if ((fstat(fd, &st)) == -1) {
                perror("fstat");
                exit(-1);
            }

            fprintf(stdout, "write flash (%d (0x%x) Bytes)\r\n", (uint32_t)st.st_size, (uint32_t)st.st_size);

            if ((flash_buf = malloc(SPI_FLASH_SECTOR_ALIGN_UP(st.st_size))) == NULL) {
                perror("malloc");
                exit(-1);
            }

            memset(flash_buf, 0, SPI_FLASH_SECTOR_ALIGN_UP(st.st_size));

            if (read(fd, flash_buf, st.st_size) != st.st_size) {
                perror("read");
                exit(-1);
            }

            /* FIXME: overflow check */
            sector_num = SPI_FLASH_SECTOR_ALIGN_UP(st.st_size) / SPI_FLASH_SECTOR_SIZE;

            icelink_flash_write_sectors(flash_offset, sector_num, flash_buf);

            close(fd);

        } else if (op_mode == 2) { /* erase chip */
            fprintf(stdout, "erase chip\n");
            icelink_flash_erase_chip();
        } else if (op_mode == 3) { /* probe chip */
            fprintf(stdout, "probe chip\n");

            icelink_sys_get_board_type();
            icelink_flash_get_info(0);

            icelink_dump_board_info(board_type, flash_id);

        }

    }

    fprintf(stdout, "done\n");

    //icelink_ram_dump();
    icelink_close();
    if (flash_buf) { 
        free(flash_buf); 
    }


    return 0;
}

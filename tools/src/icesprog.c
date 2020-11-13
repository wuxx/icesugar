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

#define ID_DAP_Vendor13 0x8DU

#define SPI_FLASH_SIZE          flash_size
#define SPI_FLASH_SECTOR_SIZE   (4096)
#define SPI_FLASH_SECTOR_ALIGN_UP(x)     ((x + SPI_FLASH_SECTOR_SIZE - 1) & (~(SPI_FLASH_SECTOR_SIZE - 1)))
#define SPI_FLASH_SECTOR_ALIGN_DOWN(x)   ((x) & (~(SPI_FLASH_SECTOR_SIZE - 1)))

enum ICELINK_CMD_E {
    CMD_FLASH_GET_INFO = 0,
    CMD_FLASH_TRANSACTION_START,
    CMD_FLASH_TRANSACTION_END,
    CMD_RAM_WRITE,
    CMD_RAM_READ,
    CMD_FLASH_WRITE_SECTOR,
    CMD_FLASH_READ_SECTOR,
    CMD_FLASH_ERASE_CHIP,
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

int icelink_flash_get_info()
{
    struct icelink_packet_head *ph;

    ph = (struct icelink_packet_head *)&icelink_handle.packet_buffer[1];

    ph->vendor_cmd  = ID_DAP_Vendor13;
    ph->icelink_cmd = CMD_FLASH_GET_INFO;

    if (icelink_usb_xfer(3) != 0) {
        fprintf(stderr, "iCELink CMD_FLASH_GET_INFO failed.");
        return -1;
    }

    flash_id = *((uint32_t *)(&(icelink_handle.packet_buffer[2])));

    fprintf(stdout, "flash id: 0x%x \n", flash_id);
    switch (flash_id) {
        case (0xEF4015):
            fprintf(stdout, "w25q16 (4MB)\n");
            flash_size = 4 * 1024 * 1024;
            break;
        case (0xEF4017):
            fprintf(stdout, "w25q64 (8MB)\n");
            flash_size = 8 * 1024 * 1024;
            break;
        case (0xEF4018):
            fprintf(stdout, "w25q128 (16MB)\n");
            flash_size = 16 * 1024 * 1024;
            break;
        default:
            fprintf(stdout, "unknown (??MB)\n");
            break;
    }

    return 0;
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
             -w | --write                   write spi-flash                              \n\
             -r | --read                    read  spi-flash                              \n\
             -e | --erase                   erase spi-flash                              \n\
             -p | --probe                   probe spi-flash                              \n\
             -o | --offset                  spi-flash offset                  			 \n\
             -l | --len                     len of write/read                            \n\
             -h | --help                    display help info                            \n\n\
             -- version 1.0 --\n\
"), stdout);
    exit(0);
}

static struct option const long_options[] =
{
  {"write",   no_argument,        NULL, 'w'},
  {"read",    no_argument,        NULL, 'r'},
  {"erase",   no_argument,        NULL, 'e'},
  {"probe",   no_argument,        NULL, 'p'},
  {"offset",  required_argument,  NULL, 'o'},
  {"len",     required_argument,  NULL, 'l'},
  {"help",    no_argument,        NULL, 'h'},
};

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

    int mode = 1; /* read: 0; write: 1; erase all: 2 */

    if (argc == 1) {
        usage(argv[0]);
        exit(-1);
    }

    while ((c = getopt_long (argc, argv, "wrpel:o:h",
                long_options, &option_index)) != -1) {
        switch (c) {
            case ('r'):
                mode = 0;
                break;
            case ('w'):
                mode = 1;
                break;
            case ('e'):
                mode = 2;
                break;
            case ('p'):
                mode = 3;
                break;
            case ('l'):
                len = strtoul(optarg, NULL, 0);
                break;
            case ('o'):
                flash_offset = strtoul(optarg, NULL, 0);
                break;
            case ('h'):
                usage(argv[0]);
                break;
            default:
                usage(argv[0]);
                break;
        }
    }

    ifile = argv[argc - 1];

    //printf("ifile: %s\r\n", ifile);
    flash_offset = SPI_FLASH_SECTOR_ALIGN_DOWN(flash_offset);


    icelink_open();

    //icelink_flash_get_info();
    //icelink_flash_dump_sector(0);

    if (mode == 0) {    /* read spi-flash */
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

        if ((fd = open(ifile, O_CREAT | O_RDWR | O_TRUNC, 0664)) == -1) {
            perror("open");
            exit(-1);
        }

        if (write(fd, flash_buf, len) != len) {
            perror("write");
            exit(-1);
        }

        close(fd);

    } else if (mode == 1) { /* write spi-flash */
        fprintf(stdout, "flash offset: 0x%08x\r\n", flash_offset);
        if ((fd = open(ifile, O_RDONLY)) == -1) {
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

    } else if (mode == 2) { /* erase chip */
        fprintf(stdout, "erase chip\n");
        icelink_flash_erase_chip();
    } else if (mode == 3) { /* probe chip */
        fprintf(stdout, "probe chip\n");
        icelink_flash_get_info();
    }

    fprintf(stdout, "done\n");

    //icelink_ram_dump();
    icelink_close();
    free(flash_buf);


    return 0;
}

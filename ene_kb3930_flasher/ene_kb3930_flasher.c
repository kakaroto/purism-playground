/*
 *
 * Copyright (C) 2018 Youness Alaoui
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; version 2 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#if !(defined __NetBSD__ || defined __OpenBSD__)
#include <sys/io.h>
#endif

#if defined __NetBSD__ || defined __OpenBSD__

#include <machine/sysarch.h>

# if defined __i386__
#  define iopl i386_iopl
# elif defined __NetBSD__
#  define iopl x86_64_iopl
# else
#  define iopl amd64_iopl
# endif

#endif

#define ENE_LPC_INDEX_BASE		0x380
#define ENE_LPC_INDEX_HIGH_ADDR		(ENE_LPC_INDEX_BASE + 1)
#define ENE_LPC_INDEX_LOW_ADDR		(ENE_LPC_INDEX_BASE + 2)
#define ENE_LPC_INDEX_DATA		(ENE_LPC_INDEX_BASE + 3)

#define ENE_XBI_SPI_ADDR_LOW		(0xFEA8)
#define ENE_XBI_SPI_ADDR_MID		(0xFEA9)
#define ENE_XBI_SPI_ADDR_HIGH		(0xFEAA)
#define ENE_XBI_SPI_DATA		(0xFEAB)
#define ENE_XBI_SPI_CMD			(0xFEAC)
#define ENE_XBI_SPI_CFG			(0xFEAD)
#define   ENE_XBI_SPI_CFG_BUSY_EN	(1 << 0)
#define   ENE_XBI_SPI_CFG_BUSY		(1 << 1)
#define   ENE_XBI_SPI_CFG_WRITE_EN	(1 << 3)

#define ENE_EC8051_PXCFG		(0xFF14)
#define   ENE_EC8051_PXCFG_RESET	(1 << 0)

#define SPI_CMD_BYTE_PROGRAM		0x02
#define SPI_CMD_READ			0x03
#define SPI_CMD_WRITE_DISABLE		0x04
#define SPI_CMD_WRITE_ENABLE		0x06
#define SPI_CMD_SECTOR_ERASE		0x20

#define SPI_FLASH_SIZE			0x10000
#define SPI_FLASH_SECTOR_SIZE		0x1000
#define SPI_FLASH_NUM_SECTORS		(SPI_FLASH_SIZE / SPI_FLASH_SECTOR_SIZE)

static uint8_t file_data[SPI_FLASH_SIZE];
static uint8_t spi_data[SPI_FLASH_SIZE];

uint8_t ec_idx_read(uint16_t addr)
{
  outb(addr & 0xff, ENE_LPC_INDEX_LOW_ADDR);
  outb(addr >> 8, ENE_LPC_INDEX_HIGH_ADDR);

  return inb(ENE_LPC_INDEX_DATA);
}

void ec_idx_write(uint16_t addr, uint8_t val)
{
  outb(addr & 0xff, ENE_LPC_INDEX_LOW_ADDR);
  outb(addr >> 8, ENE_LPC_INDEX_HIGH_ADDR);
  outb(val, ENE_LPC_INDEX_DATA);
}

static void ec_spi_wait_notbusy ()
{
  uint8_t busy = 1;
  uint8_t spicfg;

  while(busy) {
    spicfg = ec_idx_read (ENE_XBI_SPI_CFG);
    busy = spicfg & ENE_XBI_SPI_CFG_BUSY;
  }
}

uint8_t ec_spi_start()
{
  uint8_t orig_spicfg;

  orig_spicfg = ec_idx_read (ENE_XBI_SPI_CFG);
  ec_idx_write (ENE_XBI_SPI_CFG,
      orig_spicfg | ENE_XBI_SPI_CFG_BUSY_EN | ENE_XBI_SPI_CFG_WRITE_EN);
  ec_spi_wait_notbusy ();

  return orig_spicfg;
}

void ec_spi_stop(uint8_t spicfg)
{
  ec_idx_write (ENE_XBI_SPI_CFG, spicfg);
}

uint8_t ec_spi_read(uint32_t addr)
{
  ec_idx_write (ENE_XBI_SPI_ADDR_LOW, addr & 0xFF);
  ec_idx_write (ENE_XBI_SPI_ADDR_MID, (addr >> 8) & 0xFF);
  ec_idx_write (ENE_XBI_SPI_ADDR_HIGH, (addr >> 16) & 0xFF);

  ec_idx_write (ENE_XBI_SPI_CMD, SPI_CMD_READ);
  ec_spi_wait_notbusy ();
  return ec_idx_read (ENE_XBI_SPI_DATA);
}

void ec_spi_erase_sector(uint32_t addr)
{
  // Write Enable
  ec_idx_write (ENE_XBI_SPI_CMD, SPI_CMD_WRITE_ENABLE);
  ec_spi_wait_notbusy ();

  // Write
  ec_idx_write (ENE_XBI_SPI_ADDR_LOW, addr & 0xFF);
  ec_idx_write (ENE_XBI_SPI_ADDR_MID, (addr >> 8) & 0xFF);
  ec_idx_write (ENE_XBI_SPI_ADDR_HIGH, (addr >> 16) & 0xFF);
  ec_idx_write (ENE_XBI_SPI_CMD, SPI_CMD_SECTOR_ERASE);
  ec_spi_wait_notbusy ();

  // Write Disable
  ec_idx_write (ENE_XBI_SPI_CMD, SPI_CMD_WRITE_DISABLE);
}

void ec_spi_write(uint32_t addr, uint8_t value)
{
  // Write Enable
  ec_idx_write (ENE_XBI_SPI_CMD, SPI_CMD_WRITE_ENABLE);
  ec_spi_wait_notbusy ();

  // Write
  ec_idx_write (ENE_XBI_SPI_ADDR_LOW, addr & 0xFF);
  ec_idx_write (ENE_XBI_SPI_ADDR_MID, (addr >> 8) & 0xFF);
  ec_idx_write (ENE_XBI_SPI_ADDR_HIGH, (addr >> 16) & 0xFF);
  ec_idx_write (ENE_XBI_SPI_DATA, value);
  ec_idx_write (ENE_XBI_SPI_CMD, SPI_CMD_BYTE_PROGRAM);
  ec_spi_wait_notbusy ();

  // Write Disable
  ec_idx_write (ENE_XBI_SPI_CMD, SPI_CMD_WRITE_DISABLE);
}

void usage(const char *name)
{
  printf("Usage: %s [-r|-w] filename\n", name);
  printf("\n"
      "   -r <filename>      Read EC SPI Flash and write to file\n"
      "   -w <filename>      Write file contents to EC SPI Flash\n"
      "\n");
  exit(1);
}

int main(int argc, char *argv[])
{
  int i, j;
  char *filename = NULL;
  int write = 0;
  int ret = 0;
  int retries = 3;

  if (argc != 3 || argv[1][0] != '-' || strlen (argv[1]) != 2) {
    usage (argv[0]);
    exit (1);
  }

  filename = argv[2];
  if (argv[1][1] == 'w')
    write = 1;
  else if (argv[1][1] != 'r') {
    usage (argv[0]);
    exit (1);
  }

  if (iopl(3)) {
    printf("You need to be root.\n");
    exit(1);
  }
  if (write == 0) {
    FILE *f = fopen (filename, "wb");

    printf("Reading SPI flash into : %s\n", filename);
    if (f) {
      uint8_t spicfg = ec_spi_start ();

      for (i = 0; i < SPI_FLASH_SIZE; i++) {
        uint8_t d = ec_spi_read(i);
        if (fwrite (&d, 1, 1, f) != 1) {
          perror ("Error writing data to file");
          ret = -2;
        }
      }
      ec_spi_stop (spicfg);
      fclose (f);
    } else {
      perror ("Can't open read file");
      ret = -1;
    }
  } else {
    FILE *f = fopen (filename, "rb");
    int reset = 0;

    if (f) {
      fseek (f, 0, SEEK_END);
      if (ftell (f) == SPI_FLASH_SIZE) {
      retry_from_here:
        fseek (f, 0, SEEK_SET);
        if (fread (file_data, SPI_FLASH_SIZE, 1, f) == 1) {
          uint8_t spicfg = ec_spi_start ();

          printf ("Reading old flash contents");
          fflush (stdout);
          for (i = 0; i < SPI_FLASH_SIZE; i++) {
            spi_data[i] = ec_spi_read(i);
            if (i % SPI_FLASH_SECTOR_SIZE == 0) {
              printf (".");
              fflush (stdout);
            }
          }
          printf ("DONE.\n");
          for (i = 0; i < SPI_FLASH_NUM_SECTORS; i++) {
            int need_erase = 0;
            int need_write = 0;
            int is_erased = 1;

            for (j = 0; j < SPI_FLASH_SECTOR_SIZE; j++) {
              int idx = i * SPI_FLASH_SECTOR_SIZE + j;

              if (spi_data[idx] != 0xFF)
                is_erased = 0;
              if (spi_data[idx] != file_data[idx]) {
                need_write = 1;
                if ((spi_data[idx] & file_data[idx]) != file_data[idx])
                  need_erase = 1;
              }
            }
            if (need_write && reset == 0) {
              // Once the EC is reset, everything will freeze until
              // we resume it, at which point, it will shutdown
              uint8_t ctrl;
              printf ("Resetting the EC\n");
              ctrl = ec_idx_read (ENE_EC8051_PXCFG);
              ec_idx_write (ENE_EC8051_PXCFG, ctrl | ENE_EC8051_PXCFG_RESET);
              reset = 1;
            }

            if (need_erase && !is_erased) {
              printf ("Erasing sector %d\n", i);
              ec_spi_erase_sector(i * SPI_FLASH_SECTOR_SIZE);
              memset (spi_data + i * SPI_FLASH_SECTOR_SIZE,
                  0xFF, SPI_FLASH_SECTOR_SIZE);
            }
            if (need_write) {
              printf ("Writing sector %d\n", i);
              for (j = 0; j < SPI_FLASH_SECTOR_SIZE; j++) {
                int idx = i * SPI_FLASH_SECTOR_SIZE + j;

                if (spi_data[idx] != file_data[idx])
                  ec_spi_write(idx, file_data[idx]);
              }
            }
          }
          if (reset) {
            uint8_t ctrl;
            int verify_fail = -1;

            printf ("Verifying firmware");
            fflush (stdout);
            for (i = 0; i < SPI_FLASH_SIZE; i++) {
              uint8_t d = ec_spi_read(i);
              if (d != file_data[i]) {
                verify_fail = i;
                break;
              }
              if (i % SPI_FLASH_SECTOR_SIZE == 0) {
                printf (".");
                fflush (stdout);
              }
            }
            ec_spi_stop (spicfg);
            if (verify_fail != -1) {
              printf ("FAILED at 0x%X\n", verify_fail);

              if (retries-- > 0)
                goto retry_from_here;
            } else {
              printf ("DONE\n");
            }
            printf ("Resuming the EC.\n");
            printf ("Machine will probably forcibly shut down.\n");
            ctrl = ec_idx_read (ENE_EC8051_PXCFG);
            ec_idx_write (ENE_EC8051_PXCFG, ctrl & ~ENE_EC8051_PXCFG_RESET);
          } else {
            printf ("EC image is identical to input file\n");
          }
          ec_spi_stop (spicfg);
        } else {
          printf ("Error reading from input file\n");
          ret = -2;
        }
      } else {
        printf ("write file has wrong size : %lX\n", ftell (f));
        ret = -2;
      }
      fclose (f);
    } else {
      perror ("Can't open write file");
      ret = -1;
    }
  }

  return ret;
}

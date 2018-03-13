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

uint8_t ec_idx_read(uint16_t addr)
{
  uint16_t lpc_idx = 0x380;

  outb(addr & 0xff, lpc_idx + 2);
  outb(addr >> 8, lpc_idx + 1);

  return inb(lpc_idx + 3);
}

void ec_idx_write(uint16_t addr, uint8_t val)
{
  uint16_t lpc_idx = 0x380;

  outb(addr & 0xff, lpc_idx + 2);
  outb(addr >> 8, lpc_idx + 1);
  outb(val, lpc_idx + 3);
}

static void ec_spi_wait_notbusy ()
{
  uint8_t busy = 1;
  uint8_t spicfg;

  while(busy) {
    spicfg = ec_idx_read (0xFEAD);
    busy = spicfg & 0x2;
  }
}

uint8_t ec_spi_start()
{
  uint8_t orig_spicfg;

  orig_spicfg = ec_idx_read (0xFEAD);
  ec_idx_write (0xFEAD, orig_spicfg | 0x09);
  ec_spi_wait_notbusy ();

  return orig_spicfg;
}

void ec_spi_stop(uint8_t spicfg)
{
  ec_idx_write (0xFEAD, spicfg);
}

uint8_t ec_spi_read(uint32_t addr)
{
  ec_idx_write (0xFEA8, addr & 0xFF);
  ec_idx_write (0xFEA9, (addr >> 8) & 0xFF);
  ec_idx_write (0xFEAA, (addr >> 16) & 0xFF);

  ec_idx_write (0xFEAC, 0x3);
  ec_spi_wait_notbusy ();
  return ec_idx_read (0xFEAB);
}

void ec_spi_erase_sector(uint32_t addr)
{
  // Write Enable
  ec_idx_write (0xFEAC, 0x6);
  ec_spi_wait_notbusy ();

  // Write
  ec_idx_write (0xFEA8, addr & 0xFF);
  ec_idx_write (0xFEA9, (addr >> 8) & 0xFF);
  ec_idx_write (0xFEAA, (addr >> 16) & 0xFF);
  ec_idx_write (0xFEAC, 0x20);
  ec_spi_wait_notbusy ();

  // Write Disable
  ec_idx_write (0xFEAC, 0x4);
}

void ec_spi_write(uint32_t addr, uint8_t value)
{
  // Write Enable
  ec_idx_write (0xFEAC, 0x6);
  ec_spi_wait_notbusy ();

  // Write
  ec_idx_write (0xFEA8, addr & 0xFF);
  ec_idx_write (0xFEA9, (addr >> 8) & 0xFF);
  ec_idx_write (0xFEAA, (addr >> 16) & 0xFF);
  ec_idx_write (0xFEAB, value);
  ec_idx_write (0xFEAC, 0x2);
  ec_spi_wait_notbusy ();

  // Write Disable
  ec_idx_write (0xFEAC, 0x4);
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

      for (i = 0; i < 0x10000; i++) {
        uint8_t d;
        d = ec_spi_read(i);
        fwrite (&d, 1, 1, f);
      }
      ec_spi_stop (spicfg);
      fclose (f);
    } else {
      perror ("Can't open read file");
    }
  } else {
    FILE *f = fopen (filename, "rb");
    int reset = 0;

    if (f) {
      fseek (f, 0, SEEK_END);
      if (ftell (f) == 0x10000) {
        uint8_t data[0x10000];
        uint8_t spi_data[0x1000];

        fseek (f, 0, SEEK_SET);
        if (fread (data, 0x10000, 1, f) == 1) {
          uint8_t spicfg = ec_spi_start ();

          for (i = 0; i < 0x10; i++) {
            int need_erase = 0;
            int need_write = 0;
            int is_erased = 1;

            for (j = 0; j < 0x1000; j++) {
              uint8_t byte = data[i * 0x1000 + j];
              spi_data[j] = ec_spi_read(i * 0x1000 + j);
              if (spi_data[j] != 0xFF)
                is_erased = 0;
              if (spi_data[j] != byte) {
                need_write = 1;
                if ((spi_data[j] & byte) != byte)
                  need_erase = 1;
              }
            }
            if (need_write && reset == 0) {
              // One EC is reset, everything will freeze until
              // we resume it, at which point, it will shutdown
              uint8_t ctrl;
              printf ("Resetting the EC\n");
              ctrl = ec_idx_read (0xFF14);
              ec_idx_write (0xFF14, ctrl | 1); // reset
              reset = 1;
            }

            if (need_erase && !is_erased) {
              printf ("Erasing sector %d\n", i);
              ec_spi_erase_sector(i * 0x1000);
              memset (spi_data, 0xFF, 0x1000);
            }
            if (need_write) {
              printf ("Writing sector %d\n", i);
              for (j = 0; j < 0x1000; j++) {
                uint8_t byte = data[i * 0x1000 + j];

                if (spi_data[j] != byte)
                  ec_spi_write(i * 0x1000 + j, byte);
              }
            }
          }
          ec_spi_stop (spicfg);
          if (reset) {
            uint8_t ctrl;

            printf ("Resuming the EC.\n");
            printf ("Machine will probably forcibly shut down.\n");
            ctrl = ec_idx_read (0xFF14);
            ec_idx_write (0xFF14, ctrl & ~1); // execute
          } else {
            printf ("EC image is identical to input file\n");
          }
        } else {
          printf ("Error reading from input file\n");
        }
      } else {
        printf ("write file has wrong size : %lX\n", ftell (f));
      }
      fclose (f);
    } else {
      perror ("Can't open write file");
    }
  }

  return 0;
}

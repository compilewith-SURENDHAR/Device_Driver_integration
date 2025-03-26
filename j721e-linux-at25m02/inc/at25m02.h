#ifndef AT25M02_H
#define AT25M02_H

#include <linux/spi/spi.h>
#include <linux/types.h>

#define AT25M02_SIZE         (256 * 1024)   // 256 KB EEPROM
#define AT25M02_PAGE_SIZE    256            // Page size is 256 bytes
#define AT25M02_WRITE_DELAY  5              // Write cycle time (ms)

// SPI Commands for AT25M02
#define AT25M02_CMD_READ     0x03  // Read Data
#define AT25M02_CMD_WRITE    0x02  // Write Data
#define AT25M02_CMD_WREN     0x06  // Write Enable
#define AT25M02_CMD_RDSR     0x05  // Read Status Register

// Status Register Bits
#define AT25M02_STATUS_WIP   0x01  // Write In Progress

// EEPROM Device Structure
struct at25m02 {
    struct spi_device *spi;  // SPI device structure
};

// Function Prototypes
int at25m02_read(struct at25m02 *eeprom, u16 addr, u8 *buf, size_t len);
int at25m02_write(struct at25m02 *eeprom, u16 addr, const u8 *buf, size_t len);
int at25m02_probe(struct spi_device *spi);
void at25m02_remove(struct spi_device *spi);

#endif  // AT25M02_H
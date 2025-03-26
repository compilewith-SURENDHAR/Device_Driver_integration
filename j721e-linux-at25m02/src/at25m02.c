#include <linux/module.h>
#include <linux/spi/spi.h>
#include <linux/delay.h>
#include <linux/slab.h>
#include "../inc/at25m02.h"


// Write Enable Function
static int at25m02_write_enable(struct at25m02 *eeprom)
{
    u8 cmd = AT25M02_CMD_WREN;
    return spi_write(eeprom->spi, &cmd, 1);
}


// Read Status Register (Check if EEPROM is busy)
static int at25m02_read_status(struct at25m02 *eeprom)
{
    u8 cmd = AT25M02_CMD_RDSR;
    u8 status;
    struct spi_transfer xfers[] = {
        { .tx_buf = &cmd, .len = 1 },
        { .rx_buf = &status, .len = 1 },
    };
    struct spi_message msg;

    spi_message_init(&msg);
    spi_message_add_tail(&xfers[0], &msg);
    spi_message_add_tail(&xfers[1], &msg);
    int ret = spi_sync(eeprom->spi, &msg);
    if (ret < 0)
        return ret;
    return status;
}


// Wait for Write Completion
static int at25m02_wait_ready(struct at25m02 *eeprom)
{
    int timeout = 100;  // Max 100ms wait
    do {
        int status = at25m02_read_status(eeprom);
        if (status < 0)
            return status;  // Error reading status
        if (!(status & AT25M02_STATUS_WIP))
            return 0;  // Write complete
        msleep(1);
    } while (--timeout > 0);

    dev_err(&eeprom->spi->dev, "Timeout waiting for EEPROM ready\n");
    return -ETIMEDOUT;
}


// Read Function
int at25m02_read(struct at25m02 *eeprom, u16 addr, u8 *buf, size_t len)
{
    u8 cmd[3] = { AT25M02_CMD_READ, (addr >> 8) & 0xFF, addr & 0xFF };
    struct spi_transfer xfers[] = {
        { .tx_buf = cmd, .len = 3 },
        { .rx_buf = buf, .len = len },
    };
    struct spi_message msg;

    if (addr + len > AT25M02_SIZE) {
        dev_err(&eeprom->spi->dev, "Read exceeds EEPROM size\n");
        return -EINVAL;
    }

    spi_message_init(&msg);
    spi_message_add_tail(&xfers[0], &msg);
    spi_message_add_tail(&xfers[1], &msg);
    return spi_sync(eeprom->spi, &msg);
}
EXPORT_SYMBOL(at25m02_read);


// Write Function
int at25m02_write(struct at25m02 *eeprom, u16 addr, const u8 *buf, size_t len)
{
    u8 cmd[3] = { AT25M02_CMD_WRITE, (addr >> 8) & 0xFF, addr & 0xFF };
    struct spi_transfer xfers[] = {
        { .tx_buf = cmd, .len = 3 },
        { .tx_buf = buf, .len = len },
    };
    struct spi_message msg;
    int ret;

    if (addr + len > AT25M02_SIZE) {
        dev_err(&eeprom->spi->dev, "Write exceeds EEPROM size\n");
        return -EINVAL;
    }
    if (len > AT25M02_PAGE_SIZE) {
        dev_err(&eeprom->spi->dev, "Write exceeds page size\n");
        return -EINVAL;
    }

    // Enable writing
    ret = at25m02_write_enable(eeprom);
    if (ret < 0)
        return ret;

    spi_message_init(&msg);
    spi_message_add_tail(&xfers[0], &msg);
    spi_message_add_tail(&xfers[1], &msg);
    ret = spi_sync(eeprom->spi, &msg);
    if (ret < 0)
        return ret;

    // Wait for write to complete
    return at25m02_wait_ready(eeprom);
}
EXPORT_SYMBOL(at25m02_write);


// Probe Function
int at25m02_probe(struct spi_device *spi)
{
    struct at25m02 *eeprom;

    eeprom = devm_kzalloc(&spi->dev, sizeof(struct at25m02), GFP_KERNEL);
    if (!eeprom)
        return -ENOMEM;

    eeprom->spi = spi;
    spi_set_drvdata(spi, eeprom);

    // Basic sanity check
    int status = at25m02_read_status(eeprom);
    if (status < 0) {
        dev_err(&spi->dev, "Failed to read status: %d\n", status);
        return status;
    }

    dev_info(&spi->dev, "AT25M02 EEPROM initialized, status: 0x%02x\n", status);
    return 0;
}


// Remove Function
void at25m02_remove(struct spi_device *spi)
{
    dev_info(&spi->dev, "AT25M02 EEPROM removed\n");
}


// SPI Device Table
static const struct spi_device_id at25m02_id[] = {
    { "at25m02", 0 },
    { }
};
MODULE_DEVICE_TABLE(spi, at25m02_id);


// SPI Driver Structure
static struct spi_driver at25m02_driver = {
    .driver = {
        .name = "at25m02",
        .owner = THIS_MODULE,
    },
    .probe = at25m02_probe,
    .remove = at25m02_remove,
    .id_table = at25m02_id,
};


// Register the SPI Driver
module_spi_driver(at25m02_driver);


MODULE_LICENSE("GPL");
MODULE_AUTHOR("Surendhar");
MODULE_DESCRIPTION("SPI Driver for AT25M02 EEPROM");
MODULE_VERSION("1.0");
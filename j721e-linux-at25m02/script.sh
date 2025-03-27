#!/bin/bash

# Variables
HOME_PATH="/opt/sdk"
SDK_PATH="${HOME_PATH}/ti-processor-sdk-linux-adas-j721e-evm-10_01_00_04"
SPI_PATH="${SDK_PATH}/board-support/ti-linux-kernel-6.6.44+git-ti/drivers/spi"
DTS_PATH="${SDK_PATH}/board-support/ti-linux-kernel-6.6.44+git-ti/arch/arm64/boot/dts/ti"
DRV_PATH="${HOME_PATH}"
OUTPUT_PATH="${HOME_PATH}"
#---------------------------------------------------------------------------------------------------------------------------------------

# Hardcoded inputs
SOC="j721e"
DEVICE="at25m02"
OS="linux"
INTERFACE="spi"
echo "Integrating driver for SoC: $SOC, Device: $DEVICE, OS: $OS, Interface: $INTERFACE"

# Create directories in the SPI path
mkdir -p "${SPI_PATH}/external_driver/src" || { echo "Failed to create src directory"; exit 1; }
mkdir -p "${SPI_PATH}/external_driver/inc" || { echo "Failed to create inc directory"; exit 1; }

# Move the driver files into the SDK
if [ -d "$DRV_PATH" ]; then
    echo "Moving driver to SDK"
    cp "${DRV_PATH}/${DEVICE}.c" "${SPI_PATH}/external_driver/src/" || { echo "Failed to copy ${DEVICE}.c"; exit 1; }
    cp "${DRV_PATH}/${DEVICE}.h" "${SPI_PATH}/external_driver/inc/" || { echo "Failed to copy ${DEVICE}.h"; exit 1; }
    echo "Files moved successfully."
else
    echo "Driver source folder does not exist at $DRV_PATH."
    exit 1
fi
#---------------------------------------------------------------------------------------------------------------------------------------

# Update the SPI Makefile
SPI_MAKEFILE="${SPI_PATH}/Makefile"
if [ -f "$SPI_MAKEFILE" ]; then
    echo "Updating SPI Makefile at $SPI_MAKEFILE"
    if ! grep -q "at25m02.o" "$SPI_MAKEFILE"; then
        echo "obj-\$(CONFIG_SPI_AT25M02) += external_driver/src/at25m02.o" >> "$SPI_MAKEFILE"
        echo "Makefile updated with AT25M02 driver."
    else
        echo "AT25M02 driver already in Makefile."
    fi
else
    echo "SPI Makefile not found at $SPI_MAKEFILE."
    exit 1
fi
#---------------------------------------------------------------------------------------------------------------------------------------

# Update the SPI Kconfig
KCONFIG="${SPI_PATH}/Kconfig"
if [ -f "$KCONFIG" ]; then
    echo "Updating Kconfig at $KCONFIG"
    # Check if config SPI_AT25M02 already exists
    if ! grep -q "^[[:space:]]*config SPI_AT25M02[[:space:]]*$" "$KCONFIG"; then
        # Insert the new entry before exactly 'endif # SPI'
        sed -i '/^endif # SPI$/i \
config SPI_AT25M02\n\
\ttristate "AT25M02 SPI EEPROM Driver"\n\
\tdepends on SPI\n\
\thelp\n\
\t  This enables support for the AT25M02 SPI EEPROM driver.\n' "$KCONFIG" || { echo "Failed to update Kconfig"; exit 1; }
        echo "Kconfig updated with AT25M02 driver."
    else
        echo "SPI_AT25M02 already configured in Kconfig."
    fi
else
    echo "Kconfig not found at $KCONFIG."
    exit 1
fi
#---------------------------------------------------------------------------------------------------------------------------------------

# Update the Device Tree (k3-j721e-common-proc-board.dts)
DTS_FILE="${DTS_PATH}/k3-j721e-common-proc-board.dts"
if [ -f "$DTS_FILE" ]; then
    echo "Updating Device Tree at $DTS_FILE for SPI1 pinmux and AT25M02"
    # Insert spi1_pins_default as the first entry inside &main_pmx0
    if ! grep -q "spi1_pins_default: spi1-pins-default" "$DTS_FILE"; then
        sed -i '/&main_pmx0 {/a \
    spi1_pins_default: spi1-pins-default {\
        pinctrl-single,pins = <\
            J721E_IOPAD(0x1c0, PIN_INPUT, 0)  /* SPI1_CLK */\
            J721E_IOPAD(0x1c4, PIN_INPUT, 0)  /* SPI1_D0 (MISO) */\
            J721E_IOPAD(0x1c8, PIN_OUTPUT, 0) /* SPI1_D1 (MOSI) */\
            J721E_IOPAD(0x1cc, PIN_OUTPUT, 0) /* SPI1_CS0 */\
        >;\
    };' "$DTS_FILE" || { echo "Failed to insert spi1_pins_default into &main_pmx0"; exit 1; }
        echo "Inserted spi1_pins_default as first entry in &main_pmx0."
    else
        echo "spi1_pins_default already exists in Device Tree."
    fi

    if ! grep -q "&main_spi1" "$DTS_FILE"; then
        cat << 'EOF' >> "$DTS_FILE"
/* SPI1 node for AT25M02 */
&main_spi1 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&spi1_pins_default>;
    at25m02@0 {
        compatible = "at25m02";
        reg = <0>;
        spi-max-frequency = <5000000>;
    };
};
EOF
        echo "Appended &main_spi1 node."
    fi
else
    echo "Device Tree file not found at $DTS_FILE."
    exit 1
fi
#---------------------------------------------------------------------------------------------------------------------------------------

# Configure the kernel
echo "Configuring the kernel for J721E with AT25M02..."
cd "${SDK_PATH}/board-support/ti-linux-kernel-6.6.44+git-ti" || { echo "Failed to cd to kernel path"; exit 1; }
cp arch/arm64/configs/defconfig .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig || { echo "First olddefconfig failed"; exit 1; }
echo "Manually enabling CONFIG_SPI_AT25M02..."
echo "CONFIG_SPI_AT25M02=y" >> .config || { echo "Failed to append CONFIG_SPI_AT25M02"; exit 1; } 
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig || { echo "Second olddefconfig failed"; exit 1; }
echo "configuring the kernel is done"
#---------------------------------------------------------------------------------------------------------------------------------------

# Build the kernel and Device Tree
echo "Building kernel and Device Tree..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image dtbs || { echo "Build failed"; exit 1; }
#---------------------------------------------------------------------------------------------------------------------------------------

# Package the output
echo "Packaging the modified SDK..."
cd "${HOME_PATH}"
tar -czvf "${OUTPUT_PATH}/sdk_j721e_linux_atm02.tar.gz" "${SDK_PATH}"
 
echo "Process completed successfully."
exit 0

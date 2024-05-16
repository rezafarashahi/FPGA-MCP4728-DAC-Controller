"""
This Python script tests the MCP4728A0T-E/UN microchip, a 12-bit digital-to-analog converter (DAC) with 4 channels.
It communicates with an FPGA using UART to send voltage values, which configure the DAC via the I2C protocol.
The script generates and transmits dynamic voltage values to produce corresponding analog outputs from the DAC.
"""


import serial
import time
import numpy as np



def open_ser(bits):
    ser = serial.Serial(
            # Update this to match the device port for the FPGA board
            port='COM6',
            baudrate=115200,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            bytesize=serial.EIGHTBITS,
        )
    ser.write(bits)
    ser.inWaiting()
    ser.close()
    
    
def to_12_bit_binary(number):
    """Convert an integer to a 12-bit binary string.

    Args:
    number (int): The number to convert.

    Returns:
    str: The 12-bit binary representation of the number.
    """
    return f"{number:012b}"  # 012b means a binary format padded with zeros to 12 bits
    
    
def binary_to_decimal(binary_string):
    """Convert a binary string to a decimal integer.
    
    Args:
    binary_string (str): The binary string to convert.

    Returns:
    int: The decimal (base 10) representation of the binary string.
    """
    return int(binary_string, 2)
    
    

if __name__ == '__main__':

    imax = 2000
    for i in range(imax):

        time.sleep(20/1000)
        chan1_v = 1 + 1*np.sin(i/imax*10*np.pi)
        chan2_v = 1 + 1*np.cos(i/imax*300*np.pi)
        chan3_v = 0
        chan4_v = chan1_v * chan2_v
        
        chan1 = int(chan1_v/5*4095)
        chan2 = int(chan2_v/5*4095)
        chan3 = int(chan3_v/5*4095)
        chan4 = int(chan4_v/5*4095)
        
        open_ser([binary_to_decimal(to_12_bit_binary(chan4)[4:]),
                  binary_to_decimal(to_12_bit_binary(chan4)[0:4]),
                  71,
                  binary_to_decimal(to_12_bit_binary(chan3)[4:]),
                  binary_to_decimal(to_12_bit_binary(chan3)[0:4]),
                  69,
                  binary_to_decimal(to_12_bit_binary(chan2)[4:]),
                  binary_to_decimal(to_12_bit_binary(chan2)[0:4]),
                  67,
                  binary_to_decimal(to_12_bit_binary(chan1)[4:]),
                  binary_to_decimal(to_12_bit_binary(chan1)[0:4]),
                  65])
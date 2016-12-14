#!/usr/bin/python

import sys
import csv
import binascii

class DataBuilder(object):
    def __init__(self):
        self.data = []

    def add_data(self, data, offset):
        padding = offset - len(self.data)
        if padding > 0:
            self.data.extend([None] * padding)
        self.data[offset:offset+len(data)] = data

    def stats(self):
        print "Data has maximum of : %X" % len(self.data)
        start = None
        total = 0
        for i in xrange(len(self.data)):
            if start is None and self.data[i] is not None:
                start = i
            if start is not None and self.data[i] is None:
                print "Range of data: %X to %X" % (start, i)
                total += i - start
                start = None
        if start is not None:
            print "Range of data: %X to %X" % (start, len(self.data))
            total += len(self.data) - start
        print "Total bytes of data : %X (%.2f%%)" % (total, float(total) * 100 / len(self.data))

    def write(self, filename):
        with open(filename, 'wb') as f:
            start = None
            for i in xrange(len(self.data)):
                if start is None and self.data[i] != None:
                    start = i
                if start is not None and self.data[i] == None:
                    f.seek(start)
                    data = binascii.a2b_hex(''.join(self.data[start:i]))
                    f.write(data)
                    start = None
            if start is not None:
                f.seek(start)
                data = binascii.a2b_hex(''.join(self.data[start:]))
                f.write(data)

class SPIFlash(object):
    SENDING_COMMAND = 1
    SENDING_ARGS = 2
    RECEIVING_DATA = 3

    COMMANDS = {'5A': 'Read SFDP Register',
                '03': 'Read Data',
                'BB': 'Fast Read Dual I/O',
                '9F': 'JEDEC ID',
                '05': 'Read Status Register-1',
                '35': 'Read Status Register-2',
                '06': 'Write Enable',
                '02': 'Page Program',
                '90': 'Read Manufacturer/Device ID',
                '00': '***Unknown***',
                'AB': 'Release Powerdown/ID'}

    def __init__(self):
        self.builder = DataBuilder()
        self.reset()

    def reset(self):
        self.command = ''
        self.state = self.SENDING_COMMAND
        self.arglen = 0
        self.dummy = 0
        self.reading = False
        self.dual = False
        self.args = []
        self.data = []

    def parse_byte(self, DI, DO):
        if self.state == self.SENDING_COMMAND:
            self.command = DI
            if self.command == '5A':
                self.state = self.SENDING_ARGS
                self.arglen = 3
                self.dummy = 1
                self.reading = True
            elif self.command == '03':
                self.state = self.SENDING_ARGS
                self.arglen = 3
                self.reading = True
            elif self.command == 'BB':
                self.state = self.SENDING_ARGS
                self.arglen = 4
                self.reading = True
                self.dual = True
            elif self.command == '9F' or \
                 self.command == '05' or \
                 self.command == '35':
                self.state = self.RECEIVING_DATA
                self.arglen = 0
                self.reading = True
            elif self.command == '06' or \
                 self.command == '00':
                self.state = self.SENDING_COMMAND
            elif self.command == '02':
                self.state = self.SENDING_ARGS
                self.arglen = 3
                self.reading = False
            elif self.command == '90':
                self.state = self.SENDING_ARGS
                self.arglen = 3
                self.reading = True
            elif self.command == 'AB':
                self.state = self.SENDING_ARGS
                self.dummy = 3
                self.reading = True
            else:
                print "Unknown command received : %s" % self.command
                sys.exit(-1)
        elif self.state == self.SENDING_ARGS:
            if self.arglen > 0:
                self.args.append(DI)
                self.arglen -= 1
            elif self.dummy > 0:
                self.dummy -= 0
            if self.arglen == 0 and self.dummy == 0:
                self.state = self.RECEIVING_DATA
        elif self.state == self.RECEIVING_DATA:
            if self.reading:
                self.data.append(DO)
            else:
                self.data.append(DI)

    def read(self, filename):
        with open(filename, "r") as csvfile:
            reader = csv.DictReader(csvfile)
            sinput = ''
            soutput = ''
            prev_clk = 1
            for row in reader:
                cs = int(row[' CS'])
                clk = int(row[' CLK'])
                mosi = int(row[' MOSI'])
                miso = int(row[' MISO'])
                ts = float(row['Time[s]'])
                if cs == 0:
                    if prev_clk == 0 and clk == 1:
                        sinput += str(mosi)
                        soutput += str(miso)
                        if self.dual and len(sinput) == 4:
                            byte = ''
                            for i in xrange(4):
                                byte += list(soutput)[i]
                                byte += list(sinput)[i]
                            DI = "%0.2X" % int(byte, 2)
                            sinput = ''
                            soutput = ''
                            self.parse_byte(DI, DI)
                        elif len(sinput) == 8:
                            DI = "%0.2X" % int(sinput, 2)
                            DO = "%0.2X" % int(soutput, 2)
                            sinput = ''
                            soutput = ''
                            self.parse_byte(DI, DO)
                else:
                    if len(sinput) > 0:
                        print "Remaining data after CS is 1"
                        print "MOSI: %s" % sinput
                        print "MISO : %s" % soutput
                        break
                    if self.command != '':
                        print "%.4f Command : %s (%s)" % (ts, self.COMMANDS[self.command], self.command)
                        if len(self.args) > 0:
                            print "Arguments : %s" % " ".join(self.args)
                        if len(self.data) > 0:
                            data = self.data
                            while len(data):
                                print " ".join(data[0:8])
                                data = data[8:]
                            if self.command == 'BB' or self.command == '03':
                                offset = int(''.join(self.args[0:3]), 16)
                                self.builder.add_data(self.data, offset)
                        if self.command == 'BB' and self.args[3] != '05':
                            print "continuation not 0"
                            break
                    sinput = ''
                    soutput = ''
                    self.command = ''
                    self.state = self.SENDING_COMMAND
                    self.arglen = 0
                    self.dummy = 0
                    self.reading = False
                    self.dual = False
                    self.args = []
                    self.data = []
                prev_clk = clk

    def write(self, filename):
        self.builder.stats()
        self.builder.write(filename)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print "Usage: %s input.csv output.bin" % sys.argv[0]
        sys.exit(-1)
    spi = SPIFlash()
    spi.read(sys.argv[1])
    spi.write(sys.argv[2])

#!/usr/bin/python3
"""Private-socket server fixture; never contacts a phone or claims USB."""
import os
import signal
import socket
import sys

assert sys.argv[1].startswith('localfilesystem:')
assert os.environ['ADB_SERVER_SOCKET'] == sys.argv[1]
assert os.environ['ADB_USB'] == '0'
assert os.environ['ADB_EMU'] == '0'
assert os.environ['ADB_MDNS_AUTO_CONNECT'] == '0'
listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
listener.bind(sys.argv[1].split(':', 1)[1])
listener.listen(1)
with open(sys.argv[2] + '.servers', 'a') as log:
    log.write(sys.argv[1] + '\n')
signal.pause()

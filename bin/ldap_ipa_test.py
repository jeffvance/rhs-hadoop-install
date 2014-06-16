#!/usr/bin/python

import socket



def main():
    ip=[(s.connect(('8.8.8.8', 80)), s.getsockname()[0], s.close()) for s in [socket.socket(socket.AF_INET, socket.SOCK_DGRAM)]][0][1]
    host=socket.gethostbyaddr(ip)
    print("IP = %s" % ip)
    print("HOST (reverse) = %s" % host[0])
    print("OK")

if __name__=='__main__':
    main()

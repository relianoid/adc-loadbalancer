��    A      $  Y   ,      �     �  O  �     �       m        �     �  +   �     �     �          $  )   :  D   d     �  X   �          #     B  7   T  '   �      �     �     �          !  $   <  -   a  /   �     �  "   �  &     2   )  '   \  #   �  !   �     �     �     	     $     8  !   V  )   x  '   �  #   �     �  +   	  '   5  &   ]  *   �     �     �     �       -        M     f     ~  $   �  *   �     �               1  X  E     �  O  �     	       m   '     �     �  +   �     �                1  )   G  D   q     �  X   �     "     0     O  7   a  '   �      �     �     �          .  $   I  -   n  /   �     �  "   �  &      2   6   '   i   #   �   !   �      �      �      !     1!     E!  !   c!  )   �!  '   �!  #   �!     �!  +   "  '   B"  &   j"  *   �"     �"     �"     �"     #  -   ,#     Z#     s#     �#  $   �#  *   �#     �#     $     '$     >$        
      0       5   2   ,       A      #   >   8             $               	              .              &             3      9   /                      +       ?       *          7       4   6       =   !   1                 (   <           ;   )   :   @      '   "      -                              %                 * advertisement injected * --interface=<if> (-i <if>): bind interface <if>
--srcip=<ip> (-s <ip>): source (real) IP address of that host
--vhid=<id> (-v <id>): virtual IP identifier (1-255)
--pass=<pass> (-p <pass>): password
--passfile=<file> (-o <file>): read password from file
--preempt (-P): becomes a master as soon as possible
--neutral (-n): don't run downscript at start if backup
--addr=<ip> (-a <ip>): virtual shared IP address
--help (-h): summary of command-line options
--advbase=<seconds> (-b <seconds>): advertisement frequency
--advskew=<skew> (-k <skew>): advertisement skew (0-255)
--upscript=<file> (-u <file>): run <file> to become a master
--downscript=<file> (-d <file>): run <file> to become a backup
--deadratio=<ratio> (-r <ratio>): ratio to consider a host as dead
--shutdown (-z): call shutdown script at exit
--daemonize (-B): run in background
--ignoreifstate (-S): ignore interface state (down, no carrier)
--nomcast (-M): use broadcast (instead of multicast) advertisements
--facility=<facility> (-f): set syslog facility (default=daemon)
--xparam=<value> (-x): extra parameter to send to up/down scripts

Sample usage:

Manage the 10.1.1.252 shared virtual address on interface eth0, with
1 as a virtual address idenfitier, mypassword as a password, and
10.1.1.1 as a real permanent address for this host.
Call /etc/vip-up.sh when the host becomes a master, and
/etc/vip-down.sh when the virtual IP address has to be disabled.

ucarp --interface=eth0 --srcip=10.1.1.1 --vhid=1 --pass=mypassword \
      --addr=10.1.1.252 \
      --upscript=/etc/vip-up.sh --downscript=/etc/vip-down.sh


Please report bugs to  Bad IP checksum Bad TTL: [%u] Bad digest - md2=[%02x%02x%02x%02x...] md=[%02x%02x%02x%02x...] - Check vhid, password and virtual IP address Bad version: [%u] Dead ratio can't be zero Error opening socket for interface [%s]: %s Ignoring vhid: [%u] Interface [%s] not found Interface name too long Invalid address: [%s] Invalid media / hardware address for [%s] Local advertised ethernet address is [%02x:%02x:%02x:%02x:%02x:%02x] No interface found Non-preferred master advertising: reasserting control of VIP with another gratuitous arp Out of memory Out of memory to create packet Password too long Preferred master advertised: going back to BACKUP state Putting MASTER DOWN (going to time out) Putting MASTER down - preemption Spawning [%s %s %s%s%s] Switching to state: BACKUP Switching to state: INIT Switching to state: MASTER Unable to compile pcap rule: %s [%s] Unable to detach from the current session: %s Unable to detach: /dev/null can't be duplicated Unable to exec %s %s %s%s%s: %s Unable to find MAC address of [%s] Unable to get hardware info about [%s] Unable to get hardware info about an interface: %s Unable to get in background: [fork: %s] Unable to get interface address: %s Unable to open interface [%s]: %s Unable to open raw device: [%s] Unable to spawn the script: %s Unknown hardware type [%u] Unknown state: [%d] Unknown syslog facility: [%s] Using [%s] as a network interface Warning: no script called when going down Warning: no script called when going up You must supply a network interface You must supply a password You must supply a persistent source address You must supply a valid virtual host id You must supply a virtual host address You must supply an advertisement time base error reading passfile %s: %s exiting: pfds[0].revents = %d exiting: poll() error: %s gettimeofday() failed: %s initializing now to gettimeofday() failed: %s ioctl SIOCGLIFCONF error ioctl SIOCGLIFNUM error master_down event in INIT state out of memory to send gratuitous ARP unable to open passfile %s for reading: %s unexpected end of file write() error #%d/%d write() has failed: %s write() in garp: %s Project-Id-Version: ucarp 1.5.2
Report-Msgid-Bugs-To: bugs@ucarp.org
POT-Creation-Date: 2010-01-31 23:04+0100
PO-Revision-Date: 2010-01-31 23:04+0100
Last-Translator: Automatically generated
Language-Team: none
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit
Plural-Forms: nplurals=2; plural=(n != 1);
 * advertisement injected * --interface=<if> (-i <if>): bind interface <if>
--srcip=<ip> (-s <ip>): source (real) IP address of that host
--vhid=<id> (-v <id>): virtual IP identifier (1-255)
--pass=<pass> (-p <pass>): password
--passfile=<file> (-o <file>): read password from file
--preempt (-P): becomes a master as soon as possible
--neutral (-n): don't run downscript at start if backup
--addr=<ip> (-a <ip>): virtual shared IP address
--help (-h): summary of command-line options
--advbase=<seconds> (-b <seconds>): advertisement frequency
--advskew=<skew> (-k <skew>): advertisement skew (0-255)
--upscript=<file> (-u <file>): run <file> to become a master
--downscript=<file> (-d <file>): run <file> to become a backup
--deadratio=<ratio> (-r <ratio>): ratio to consider a host as dead
--shutdown (-z): call shutdown script at exit
--daemonize (-B): run in background
--ignoreifstate (-S): ignore interface state (down, no carrier)
--nomcast (-M): use broadcast (instead of multicast) advertisements
--facility=<facility> (-f): set syslog facility (default=daemon)
--xparam=<value> (-x): extra parameter to send to up/down scripts

Sample usage:

Manage the 10.1.1.252 shared virtual address on interface eth0, with
1 as a virtual address idenfitier, mypassword as a password, and
10.1.1.1 as a real permanent address for this host.
Call /etc/vip-up.sh when the host becomes a master, and
/etc/vip-down.sh when the virtual IP address has to be disabled.

ucarp --interface=eth0 --srcip=10.1.1.1 --vhid=1 --pass=mypassword \
      --addr=10.1.1.252 \
      --upscript=/etc/vip-up.sh --downscript=/etc/vip-down.sh


Please report bugs to  Bad IP checksum Bad TTL: [%u] Bad digest - md2=[%02x%02x%02x%02x...] md=[%02x%02x%02x%02x...] - Check vhid, password and virtual IP address Bad version: [%u] Dead ratio can't be zero Error opening socket for interface [%s]: %s Ignoring vhid: [%u] Interface [%s] not found Interface name too long Invalid address: [%s] Invalid media / hardware address for [%s] Local advertised ethernet address is [%02x:%02x:%02x:%02x:%02x:%02x] No interface found Non-preferred master advertising: reasserting control of VIP with another gratuitous arp Out of memory Out of memory to create packet Password too long Preferred master advertised: going back to BACKUP state Putting MASTER DOWN (going to time out) Putting MASTER down - preemption Spawning [%s %s %s%s%s] Switching to state: BACKUP Switching to state: INIT Switching to state: MASTER Unable to compile pcap rule: %s [%s] Unable to detach from the current session: %s Unable to detach: /dev/null can't be duplicated Unable to exec %s %s %s%s%s: %s Unable to find MAC address of [%s] Unable to get hardware info about [%s] Unable to get hardware info about an interface: %s Unable to get in background: [fork: %s] Unable to get interface address: %s Unable to open interface [%s]: %s Unable to open raw device: [%s] Unable to spawn the script: %s Unknown hardware type [%u] Unknown state: [%d] Unknown syslog facility: [%s] Using [%s] as a network interface Warning: no script called when going down Warning: no script called when going up You must supply a network interface You must supply a password You must supply a persistent source address You must supply a valid virtual host id You must supply a virtual host address You must supply an advertisement time base error reading passfile %s: %s exiting: pfds[0].revents = %d exiting: poll() error: %s gettimeofday() failed: %s initializing now to gettimeofday() failed: %s ioctl SIOCGLIFCONF error ioctl SIOCGLIFNUM error master_down event in INIT state out of memory to send gratuitous ARP unable to open passfile %s for reading: %s unexpected end of file write() error #%d/%d write() has failed: %s write() in garp: %s 
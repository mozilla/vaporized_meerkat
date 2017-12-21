#!/bin/bash
exec sudo -u suricata -g suricata /opt/suricata/bin/suricata -c /etc/nsm/suricata.yaml --af-packet --pidfile /home/suricata/run/suricata-internal.pid

#!/bin/bash
cpu=$(</sys/class/thermal/thermal_zone0/temp)
echo "GPU => $(/opt/vc/bin/vcgencmd measure_temp | sed -E 's/.*=([0-9\.]+).*/\1/g')"
echo "CPU => $((cpu/1000))"
/opt/vc/bin/vcgencmd get_throttled

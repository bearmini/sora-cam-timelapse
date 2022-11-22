sora-cam-timepalse
==================

# How to use

```
# Device ID of your camera. You can find the device id of your camera by running `soracom sora-cam devices list` command.
device_id=7CDDxxxxxxxx

# Working directory to store downloaded image files.
work_dir=/tmp/sora-cam-timelapse-work

# Timestamps
# create a timelapse video from 2 hours ago (`start`) to 1 hour ago (`end`), as an example.
# You can modify `start` and `end` as you want.
now="$( date +%s )"
start="$(( now - 7200 ))000"
end="$(( now - 3600 ))000"

# Create a timelapse video
./sora-cam-timelapse.sh --work-dir "$work_dir" --device-id "$device_id" --start "$start" --end "$end"
```

For more detailed explanations, run `./sora-cam-timelapse.sh` without arguments.

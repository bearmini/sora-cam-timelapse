#!/usr/bin/env bash
set -Eeuo pipefail

if ! ffmpeg -version >/dev/null 2>&1; then
  echo "ffmpeg is required" 1>&2
  exit 1
fi

if ! soracom version >/dev/null 2>&1; then
  echo "soracom is required" 1>&2
  exit 1
fi

if ! jq --version >/dev/null 2>&1; then
  echo "jq is required" 1>&2
  exit 1
fi

if ! curl --version >/dev/null 2>&1; then
  echo "curl is required" 1>&2
  exit 1
fi

show_usage_and_exit() {
  cat <<EOD
usage: $0 [OPTIONS]

  OPTIONS:
    -w, --work-dir    Directory to store downloaded image files (required)
    -d, --device-id   Device ID (required)
    -s, --start       Start time (unix time in milliseconds) (required)
    -e, --end         End time (unix time in milliseconds) (required)
    -i, --interval    Time interval between images to be downloaded (unix time in milliseconds) (default: 10000)
    -f, --fps         Number of image files used to generate 1 second duration of video (default: 10)
    -o, --output      Name of generated video file (default: <work-dir>/output.mp4)
    -p, --profile     SORACOM profile to use (default: "default")

    The duration of the video artifact is calculated by the following expression:

      <duration> = (<end> - <start>) / <interval> / <fps>

    e.g.)
      if:
        <end> - <start> = 7200000 (7,200 seconds, == 2 hours)
        <interval> = 10000 (default, 10 seconds)
        <fps> = 10 (default, 10)

      then
        <duration> = (<end> - <start>) / <interval> / <fps>
                   = 7200000 / 10000 / 10
                   = 72 (seconds)

      i.e. using 2 hours source video, you will get 72 seconds timelapse video

EOD
  exit 1
}

wait_for_export_completed() {
  local export=$1
  local device_id
  local export_id

  device_id="$( echo "$export" | jq -r .deviceId )"
  export_id="$( echo "$export" | jq -r .exportId )"

  i=0
  while true; do
    status="$( echo "$export" | jq -r .status )"
    if [ "$status" == "completed" ]; then
      url="$( echo "$export" | jq -r .url )"
      echo "$url"
      echo 1>&2
      return 0
    fi
    sleep 1
    printf . 1>&2
    i=$(( i + 1 ))
    if [ "$i" -gt 60 ]; then
      echo "export has not completed within 60 seconds" 1>&2
      exit 1
    fi

    export="$( soracom --profile "$profile" sora-cam devices images get-exported --device-id "$device_id" --export-id "$export_id" )"
  done
}

download_exported_file() {
  local work_dir=$1
  local url=$2
  local timestamp=$3

  curl -sSfL -o "${work_dir}/${timestamp}.jpg" "$url"
}

abort() {
  echo "$*" >&2
  exit 1
}

unrecognized_option() {
  abort "unrecognized option '$1'"
}

arg_value_required() {
  [ $# -gt 1 ] || abort "option '$1' requires an argument value"
}

profile="default"
work_dir=""
device_id=""
start=""
end=""
interval=10000
fps=10
output=""

while [ $# -gt 0 ]; do
  case $1 in
    -w | --work-dir)  arg_value_required "$@" && shift; work_dir=$1 ;;
    -d | --device-id) arg_value_required "$@" && shift; device_id=$1 ;;
    -s | --start)     arg_value_required "$@" && shift; start=$1 ;;
    -e | --end)       arg_value_required "$@" && shift; end=$1 ;;
    -i | --interval)  arg_value_required "$@" && shift; interval=$1 ;;
    -f | --fps)       arg_value_required "$@" && shift; fps=$1 ;;
    -o | --output)    arg_value_required "$@" && shift; output=$1 ;;
    -p | --profile)   arg_value_required "$@" && shift; profile=$1 ;;
    -h | --help)      show_usage_and_exit ;;
    -?*) unrecognized_option "$@" ;;
    *) break
  esac
  shift
done

if [ -z "$work_dir" ] || [ -z "$device_id" ] || [ -z "$start" ] || [ -z "$end" ]; then
  show_usage_and_exit
fi

mkdir -p "$work_dir"

total=$(( (end - start) / interval ))
echo "Downloading total ${total} images"
i=1
curr=$start
while [ "$curr" -le "$end" ]; do
  if [ ! -s "$work_dir/${curr}.jpg" ]; then
    echo "Downloading $i / $total ..."
    cmd="soracom --profile $profile sora-cam devices images export --device-id $device_id --time $curr"
    echo "> $cmd"
    export="$( $cmd )"
    url="$( wait_for_export_completed "$export" )"
    download_exported_file "$work_dir" "$url" "$curr"
  fi
  i=$(( i + 1 ))
  curr=$(( curr + interval ))
done

resolution="$( file "${work_dir}/${start}.jpg" | \grep -oP "[[:digit:]]+x[[:digit:]]+" )"
echo "Detected resolution: $resolution"

if [ "$output" == "" ]; then
  output="${work_dir}/output.mp4"
fi
echo "Generating timelapse ..."
ffmpeg -r "$fps" -pattern_type glob -i "${work_dir}/"'*.jpg' -s "${resolution}" -vcodec libx264 "$output"

echo "Done."

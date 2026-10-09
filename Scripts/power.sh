# Embedded at build time. No runtime resource-file dependency.
# The app prepends: mode=normal|task, daily_ac=<minutes>, daily_battery=<minutes>.
set -eu
daily_ac=${daily_ac:-15}
daily_battery=${daily_battery:-5}
case "$mode" in
 normal) target_disable=0; target_tty=0;;
 task) target_disable=1; target_tty=1;;
 *) echo 'Unknown mode' >&2; exit 2;;
esac
number() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
minutes() { number "$1" && [ "$1" -ge 1 ] && [ "$1" -le 180 ]; }
minutes "$daily_ac" && minutes "$daily_battery" || { echo 'Invalid idle timer; no changes made.' >&2; exit 2; }
step='Read current settings'
snapshot=$(/usr/bin/pmset -g custom)
get_setting() {
 printf '%s\n' "$snapshot" | /usr/bin/awk -v section="$1:" -v key="$2" '
 /^[^ \t].*:$/ {active=($0==section)}
 active && $1==key {print $2; exit}'
}
get_disabled() {
 live=$(/usr/bin/pmset -g) || return 1
 printf '%s\n' "$live" | /usr/bin/awk '$1=="SleepDisabled" {print $2; found=1; exit} END {if (!found) print 0}'
}
old_disable=$(get_disabled)
number "$old_disable" || { echo 'Invalid sleep state' >&2; exit 1; }
# Only touch profiles and keys actually reported by this Mac.
# Daily mode also lowers displaysleep to the idle timer when it is longer or never (0): while the display
# is on, powerd keeps the Mac from idle sleeping, so a longer display timer would defeat the daily timer.
# Shorter display timers are left alone, and Task mode never changes displaysleep.
records=''
for section in 'AC Power' 'Battery Power' 'UPS Power'; do
 value=$(get_setting "$section" sleep)
 [ -n "$value" ] || continue
 number "$value" || exit 1
 tty=$(get_setting "$section" ttyskeepawake)
 if [ -n "$tty" ]; then number "$tty" || exit 1; else tty=skip; fi
 disp=$(get_setting "$section" displaysleep)
 if [ -n "$disp" ]; then number "$disp" || exit 1; else disp=skip; fi
 case "$section" in
  'AC Power') flag=-c; daily=$daily_ac; task=0;;
  'Battery Power') flag=-b; daily=$daily_battery; task=1;;
  'UPS Power') flag=-u; daily=$daily_ac; task=0;;
 esac
 if [ "$mode" = normal ]; then target=$daily; else target=$task; fi
 target_disp=skip
 if [ "$mode" = normal ] && [ "$disp" != skip ] && { [ "$disp" -eq 0 ] || [ "$disp" -gt "$target" ]; }; then target_disp=$target; fi
 records="${records}${flag}|${section}|${value}|${tty}|${target}|${disp}|${target_disp}
"
done
[ -n "$records" ] || { echo 'No supported power profile; no changes made.' >&2; exit 1; }
# apply_profile FLAG SLEEP TTY|skip DISPLAYSLEEP|skip
apply_profile() {
 ap_flag=$1 ap_sleep=$2 ap_tty=$3 ap_disp=$4
 set -- "$ap_flag" sleep "$ap_sleep"
 [ "$ap_tty" = skip ] || set -- "$@" ttyskeepawake "$ap_tty"
 [ "$ap_disp" = skip ] || set -- "$@" displaysleep "$ap_disp"
 /usr/bin/pmset "$@"
}
rollback() {
 code=$?
 trap - EXIT
 set +e
 echo "Failed step: $step (exit $code). Attempting rollback." >&2
 while IFS='|' read -r flag section old_sleep old_tty target old_disp target_disp; do
  [ -n "$flag" ] || continue
  disp=skip; [ "$target_disp" = skip ] || disp=$old_disp
  apply_profile "$flag" "$old_sleep" "$old_tty" "$disp" || echo "Rollback failed: $section" >&2
 done <<EOF
$records
EOF
 /usr/bin/pmset -a disablesleep "$old_disable" || echo 'Global sleep rollback failed' >&2
 /usr/bin/pmset -g >&2
 /usr/bin/pmset -g custom >&2
 exit "$code"
}
trap rollback EXIT
while IFS='|' read -r flag section old_sleep old_tty target old_disp target_disp; do
 [ -n "$flag" ] || continue
 step="Set $section"
 tty=$target_tty; [ "$old_tty" != skip ] || tty=skip
 apply_profile "$flag" "$target" "$tty" "$target_disp"
done <<EOF
$records
EOF
step='Set global sleep switch'
/usr/bin/pmset -a disablesleep "$target_disable"
step='Verify live settings'
verify() {
 snapshot=$(/usr/bin/pmset -g custom) || return 1
 [ "$(get_disabled)" = "$target_disable" ] || return 1
 while IFS='|' read -r flag section old_sleep old_tty target old_disp target_disp; do
  [ -n "$flag" ] || continue
  [ "$(get_setting "$section" sleep)" = "$target" ] || return 1
  if [ "$target_disp" != skip ]; then
   [ "$(get_setting "$section" displaysleep)" = "$target_disp" ] || return 1
  fi
  if [ "$old_tty" != skip ]; then
   [ "$(get_setting "$section" ttyskeepawake)" = "$target_tty" ] || return 1
  fi
 done <<EOF
$records
EOF
}
attempt=0
while [ "$attempt" -lt 5 ]; do
 if verify; then trap - EXIT; exit 0; fi
 attempt=$((attempt + 1))
 /bin/sleep 1
done
echo 'Live settings do not match the requested mode.' >&2
exit 1

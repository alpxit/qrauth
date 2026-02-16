#!/bin/bash
# required wayland compatible "keylogger" https://github.com/AlynxZhou/showmethekey.git
# but if qr scanner works fine, a keylogger is optional

LOGPATH=/tmp/watchtotp.log
UN=$(whoami)
SESSIONID=`loginctl list-sessions | grep $UN | awk '{print $1}'`
TOTPKEYID=$(keyctl show | grep TOTPKEY | awk '{print $1}')
ENTEREDTOTP="******"


TS=`date +%Y%m%d_%H%M%S`
echo "$TS: TOTPKEYID: $TOTPKEYID" >>$LOGPATH

# If the system time is incorrect when booting, it must be synchronized with the correct time,
# otherwise it will be impossible to unlock the computer.
while true; do
  sudo /usr/sbin/ntpdate -d pool.ntp.org >>$LOGPATH
  if [ $? -eq 0 ]; then
    break
  fi
  ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/glass-water-1.wav" 2>/dev/null &
  sleep 1
done

TS=`date +%Y%m%d_%H%M%S`
echo "$TS: just synced time" >>$LOGPATH


loginctl lock-session $SESSIONID

# for first unlock by webcamera qr scanning is ok, but if you want use it for video recording during PC lock,
# you should use another qr scanning method (with ffmpeg and zbarimg)...  for example see QRunlock.sh
(zbarcam -q --nodisplay --nodbus --raw -Sdisable -Sqrcode.enable | \
while read -r QRTOTPCODE >/dev/null; do
  NEEDTOTP=`keyctl pipe $TOTPKEYID | oathtool -s 30 -d 6 -b --totp -`
  ISLOCKED=`loginctl show-session $SESSIONID | grep LockedHint=yes`
  TS=`date +%Y%m%d_%H%M%S`
  echo "$TS: [QRTOTP: $NEEDTOTP] {$QRTOTPCODE}" >>$LOGPATH
  if [ "$QRTOTPCODE" == "$NEEDTOTP" -o -z $ISLOCKED ]; then
    ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/glass-water-1.wav" 2>/dev/null &
    loginctl unlock-session $SESSIONID
    killall -9 showmethekey-cli zbarcam
  fi
done
)&


while [ true ]; do

  sleep 10
  ISLOCKED=`loginctl show-session $SESSIONID | grep LockedHint=yes`
  if [ ! -z $ISLOCKED ]; then

    TS=`date +%Y%m%d_%H%M%S`
    echo "$TS: Lock detected, wait totp..." >>$LOGPATH
    PREVTOTPC="******"

    showmethekey-cli | \
    grep --line-buffered PRESSED | \
    awk -W interactive '{print $8; fflush(stdout)}' | \
    while read -sr keycode; do
      ENTEREDTOTP=`echo "$ENTEREDTOTP${keycode:5:1}" | tail -c+2`
      NEEDTOTP=`keyctl pipe $TOTPKEYID | oathtool -s 30 -d 6 -b --totp -`
      if [ "$PREVTOTPC" !== "$NEEDTOTP" ]; then
        PREVTOTPC=$NEEDTOTP
      fi
      ISLOCKED=`loginctl show-session $SESSIONID | grep LockedHint=yes`
      TS=`date +%Y%m%d_%H%M%S`
      echo "$TS: [TOTP: $NEEDTOTP] {$ENTEREDTOTP}" >>$LOGPATH
      if [ "$ENTEREDTOTP" == "$NEEDTOTP" -o "$ENTEREDTOTP" == "$PREVTOTPC" -o -z $ISLOCKED ]; then
        ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/glass-water-1.wav" 2>/dev/null &
        loginctl unlock-session $SESSIONID
        killall -9 showmethekey-cli zbarcam
      fi
    done

  fi

done

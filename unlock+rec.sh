#!/bin/bash

TS=`date`
IMGFMT=pgm
QRCODEPATH=/tmp/qrcode.$IMGFMT
LOGPATH=/tmp/unlockByQrCode.log
#LOGPATH="/dev/tty"
SESSID=`loginctl list-sessions | grep $(whoami) | grep user | awk '{print $1}'`
TOTPKEYID=$(keyctl show | grep TOTPKEY | awk '{print $1}')
if [ -z $TOTPKEYID ]; then
  echo "Oops... TOTP key is absent!!!! alert...."
  exit
fi

# -r 0.5 -update 1 -vf "extractplanes=y,crop=800:720:200:0,scale=400:360" $QRCODEPATH \

rm -f $QRCODEPATH

ffmpeg -loglevel quiet -hide_banner -y \
 -f v4l2 -i /dev/video0 \
 -f alsa -sample_rate 44100 -i hw:CARD=PCH,DEV=0 \
 -map 0:v -map 1:a -f segment -strftime 1 -segment_time 43200 -strict experimental \
 -segment_format mpegts -fflags +genpts+igndts -muxdelay 0.1 -ac 1 -c:a aac -b:a 256k -vf "hqdn3d" -c:v libx264 -crf 26 -preset ultrafast -tune zerolatency -bf 0 -flush_packets 1 \
 /mnt/hdd/data/camcap_%Y-%m-%d_%H-%M-%S.ts \
 -map 0:v -vf "fps=2,format=gray" -c:v $IMGFMT -f image2pipe - | \
ffmpeg -loglevel quiet -hide_banner -y \
 -f image2pipe -i - -vf "select='gt(scene,0.10)'" -update 1 -c:v $IMGFMT -f image2 $QRCODEPATH &
ffpid=$!
ffpid1=$((ffpid-1))

echo -n "5 sec pause before screen lock..."
sleep 1
echo -n "1.."
sleep 1
echo -n "2.."
sleep 1
echo -n "3.."
sleep 1
echo -n "4.."
sleep 1
echo -n "5.."
sleep 1

loginctl lock-session $SESSID

sleep 1

PREVTOTPC="******"

ISUNLOCKBYKBDACTIVE=`ps -Af | grep  showmethekey-cli | grep -v grep`
if [ -z "$ISUNLOCKBYKBDACTIVE" ]; then
(ENTEREDTOTP="******"
 showmethekey-cli | \
 grep --line-buffered PRESSED | \
 awk '{print $8; fflush(stdout)}' | \
 while read -sr keycode; do
   ENTEREDTOTP=`echo "$ENTEREDTOTP${keycode:5:1}" | tail -c+2`
   NEEDTOTP=`keyctl pipe $TOTPKEYID | oathtool -s 30 -d 6 -b --totp -`
   if [ "$PREVTOTPC" != "$NEEDTOTP" ]; then
     PREVTOTPC=$NEEDTOTP
   fi
   ISLOCKED=`loginctl show-session $SESSID | grep LockedHint=yes`
   TS=`date +%Y%m%d_%H%M%S`
   echo "$TS: [TOTP: $NEEDTOTP] {$ENTEREDTOTP}" >>$LOGPATH
   if [ "$ENTEREDTOTP" == "$NEEDTOTP" -o "$ENTEREDTOTP" == "$PREVTOTPC" -o -z $ISLOCKED ]; then
     qrencode -m 2 -t PNG -o "$QRCODEPATH" "$NEEDTOTP"
     ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/glass-water-1.wav" 2>/dev/null &
   fi
 done)&
fi

while true
do

  sleep 2

#  inotifywait -qe 'create,moved_to' -t 10 $DWNLPATH
#  inotifywait -qqe 'close' -t 10 $QRCODEPATH

  if [ ! -f "$QRCODEPATH" ]; then
    continue
  fi

  ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/pisk-down.wav" 2>/dev/null &
  TS=`date`
#  echo "$TS Wait until the file received..." >> $LOGPATH

  UNLOCKKEY=`zbarimg -q --raw $QRCODEPATH`
  rm -f $QRCODEPATH
  echo "$TS $UNLOCKKEY" >> $LOGPATH

  if [ ! -z "$UNLOCKKEY" ]; then
    THEKEY=`keyctl pipe $TOTPKEYID | oathtool -s 30 -d 6 -b --totp -`
    echo "keys need/recieved: $THEKEY==$UNLOCKKEY" >> $LOGPATH
    if [ "$THEKEY" == "$UNLOCKKEY" ]; then
      echo "unlock sessionid $SESSID" >> $LOGPATH
#      kill -SIGQUIT $ffpid
      loginctl unlock-session $SESSID
      sleep 2
      kill -9  $ffpid $ffpid1   # workaround to prevent sustem UI frizing
      if [ -z "$ISUNLOCKBYKBDACTIVE" ]; then
        killall -9 showmethekey-cli
      fi
      ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/electric-piano-3.wav" 2>/dev/null &
      exit
    else
      echo "Oops codes does not match... [$THEKEY] $UNLOCKKEY" >> $LOGPATH
      ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/cockchafer-gentleman-1.wav" 2>/dev/null &
    fi
  fi

done

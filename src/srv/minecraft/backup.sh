#!/bin/bash

# config vars

SRC="/srv/minecraft/$1/"
SNAP="/srv/minecraft/backup/$1"
OPTS="-rltgoi --delay-updates --delete --exclude-from=/srv/minecraft/backup/exclude.txt"
MINCHANGES=20

# run this process with real low priority

ionice -c 3 -p $$
renice +12  -p $$

mkdir -p "$SNAP"

# sync

time rsync $OPTS "$SRC" "$SNAP/latest" >> "$SNAP/rsync.log"

# check if enough has changed and if so
# make a hardlinked copy named as the date

COUNT=$( wc -l "$SNAP/rsync.log"|cut -d" " -f1 )
if [ $COUNT -gt $MINCHANGES ] ; then
  DATETAG=$(date +%Y-%m-%d)
  if [ ! -e "$SNAP/$DATETAG" ] ; then
    cp -al "$SNAP/latest" "$SNAP/$DATETAG"
    chmod u+w "$SNAP/$DATETAG"
    mv "$SNAP/rsync.log" "$SNAP/$DATETAG"
    chmod u-w "$SNAP/$DATETAG"
  fi
fi

# announce
echo tellraw @a '{"text": "Backup done!", "color": "green"}' > /srv/minecraft/input/$1

# run custom script (Upload to S3)
if [ -x "$SRC/post-backup.sh" ] ; then
  sudo -u minecraft "$SRC/post-backup.sh"
fi

# create external backup
if [ ! -z "$BORG_PATH" ] ; then
  borg create --progress --stats "$BORG_PATH/$1"::$(date +%Y-%m-%d) "$SNAP/latest/"*
fi

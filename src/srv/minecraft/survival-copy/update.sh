#!/bin/sh
echo Shutting down server
sudo systemctl stop minecraft@survival-copy
echo Saving persistent regions
rsync -i world --files-from=persistent.txt persistent/
echo Loading latest survival backup
rsync -avr --chown minecraft:minecraft --chmod=ug+w --delete --exclude '**playerdata/*.dat' --exclude '**carpet.conf' --exclude '**session.lock' ../backup/survival/latest/world .
#echo "worldEdit true" >> world/carpet.conf
echo Restoring persistent regions
rsync -i persistent --files-from=persistent.txt world/
echo Starting server
sudo systemctl start minecraft@survival-copy

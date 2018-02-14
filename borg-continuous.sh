#!/bin/bash

# This script will keep running until it has successfully carried out a borg backup
# The point is to survive the backup target being mostly unavailable (eg a workstation)

### CONSTANTS: ###

# SOURCE_PATHS could be something like "/ --exclude /tmp --exclude /bin"
# Or "/home/someuser --exclude /home/someuser/.cache"
SOURCE_PATHS=""
# SOURCE_USER The user which will be running the script on the backup source machine. Must have read access to the paths in SOURCE_PATHS
SOURCE_USER=""
# SOURCE_GROUP The group ditto 
SOURCE_GROUP=""
# DESTINATION_HOST The host name of the machine to which we are backing up
DESTINATION_HOST=""
# DESTINATION_USER The ssh user which will receive the backup data. Make sure to do an ssh key exchange so that borg can connect with ssh
DESTINATION_USER=""
# DESTINATION_PATH The path on the backup destination machine which has been initialized as a borg repo
DESTINATION_PATH=""
# SECONDS_BETWEEN_POLLS How long after destination boot up should the backup start on average?
SECONDS_BETWEEN_POLLS="20"
# TAG_PREFIX A prefix which will be prepended to the backups. Use this to manage specifically the backups made by this script. Can be anything.
TAG_PREFIX=""
# TAG How we tag the backups
TAG="${TAG_PREFIX}-{now:%Y-%m-%d %H:%M}"
### END OF CONSTANTS ###

REPOSITORY="$DESTINATION_USER@$DESTINATION_HOST:$DESTINATION_PATH"
PATH_OF_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Modify this function to tweak the backup pruning strategy
function carryOutPrune {
    borg prune -v --list $REPOSITORY --keep-daily=7 --keep-weekly=4 --keep-monthly=6
}

# Modify this function to tweak exactly how the backup gets carried out
function carryOutBackup {
    borg create -v --stats --compression lz4 "${REPOSITORY}::$TAG" $SOURCE_PATHS
}

# Modify this function to change how destination responsiveness checks are done
function isDestinationUp {
    ping -c 1 -W 2 "$DESTINATION_HOST" &> /dev/null
}

function keepTrying {
    while true; do
        if isDestinationUp; then
            echo "Destination is up - attempting backup"
            if carryOutBackup && carryOutPrune; then
                echo "Backup and prune successful. Exiting!"
                exit 0
            else
                echo "Backup failed - trying again in $SECONDS_BETWEEN_POLLS seconds"
            fi
        fi
        sleep "$SECONDS_BETWEEN_POLLS"
    done
}

function installService {
    contents="
[Unit]
Description=Borg Backup
 
[Service]
Type=simple
Nice=19
IOSchedulingClass=2
IOSchedulingPriority=7
ExecStartPre=$(which borg) break-lock $REPOSITORY
ExecStart=$PATH_OF_SCRIPT backup
User=$SOURCE_USER
Group=$SOURCE_GROUP
"
    sudo sh -c "echo \"$contents\" > /etc/systemd/system/borgbackup.service"
}

function installTimer {
    contents="
[Unit]
Description=Borg Backup Timer
 
[Timer]
WakeSystem=false
OnCalendar=*-*-* 06:00:00
RandomizedDelaySec=10min
 
[Install]
WantedBy=timers.target
"
    sudo sh -c "echo \"$contents\" > /etc/systemd/system/borgbackup.timer"
}

function viewLogs {
    journalctl -u borgbackup.service -u borgbackup.timer
}

mode="$1"
if [ "$mode" == "backup" ]; then
    keepTrying
elif [ "$mode" == "install" ]; then
    installService
    installTimer
    sudo systemctl daemon-reload
elif [ "$mode" == "viewlog" ]; then
    viewLogs
else
    cat <<EOF
Usage: ./$(basename "${BASH_SOURCE[0]}") backup|install|viewlog

- install generates service/timer files for scheduling the backup
- backup runs the backup routine according to the constants in the script. You can run the script manually with that argument when testing

Make sure you have set up the various variables in the script before setting up the service/timer files with 'install'

If you need to change a value in the script simply run install again afterwards

Making sure the timer starts again after boot is done with the following command (which can be run after 'install' has run):
'sudo systemctl enable borgbackup.timer'

Starting the timer is done with 
'sudo systemctl start borgbackup.timer'

Check logs with the 'viewlog' mode
EOF
fi

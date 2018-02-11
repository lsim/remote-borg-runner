# remote-borg-runner
A simple shell script for easily setting up continuous backup with [borg](https://github.com/borgbackup/borg) from one linux system to another

The specific problem I wrote this script to solve is that I want to back up my home server to one of my workstations (which has had an extra harddrive installed for the specific purpose).

Whenever the workstation is started up, the server runs a quick incremental deduplicated backup with the excellent [borg backup](https://github.com/borgbackup/borg) system.


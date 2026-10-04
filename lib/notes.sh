#!/usr/bin/env bash
# Update the target field before the notes editor is opened.
rs_notes_target() (
    local room=$1 target=$2 notes temp backup
    notes="$room/notes.md"
    [[ -f $notes && ! -L $notes ]] || return 1
    rs_validate_target "$target" || return 1
    umask 077
    temp=$(mktemp "$room/.roomstart/.notes.XXXXXXXX") || return 1
    trap 'rm -f -- "$temp"' EXIT
    awk -v target="$target" '
        /^## / { in_target = ($0 == "## Target") }
        in_target && /^IP:/ && !updated {
            print "IP: " target; updated=1; next
        }
        { print }
        END {
            if (!updated) {
                print ""; print "## Target"; print "IP: " target
            }
        }
    ' "$notes" > "$temp" || return 1
    cmp -s -- "$notes" "$temp" && return 0
    backup=$(mktemp "$room/.roomstart/notes-backup.XXXXXXXX") || return 1
    cp -p -- "$notes" "$backup" || return 1
    chmod --reference="$notes" "$temp" || return 1
    mv -fT -- "$temp" "$notes"
)

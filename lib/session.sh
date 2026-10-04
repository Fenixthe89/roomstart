#!/usr/bin/env bash
# One supervisor per visible room tool. Only this process owns role.lock.
set -u
umask 077
SESSION_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
# shellcheck source=runtime.sh
source "$SESSION_SCRIPT_DIR/runtime.sh"

# Internal entry point used by setsid and by script's PTY child. Record the
# fresh process identity before exec so cleanup can reach both Linux sessions.
if [[ ${1:-} == --child ]]; then
    [[ $# -ge 3 ]] || exit 2
    marker=$2; shift 2
    read -r process_state process_parent process_group process_session process_ticks < <(rs_runtime_proc "$$") || exit 1
    rs_runtime_atomic "$marker" "$$ $process_ticks $process_session" || exit 1
    exec "$@"
fi

[[ $# -ge 3 ]] || { rs_runtime_error 'uso interno: session.sh ROOMDIR SESSIONDIR RUOLO [ARGOMENTO]'; exit 2; }
roomdir=$1 sessiondir=$2 role=$3; shift 3
rs_runtime_role_valid "$role" || exit 2
rs_runtime_init "$roomdir" || exit 2
roomdir=$(cd -- "$roomdir" && pwd -P) || exit 2
[[ -d "$roomdir/.roomstart/sessions" && ! -L "$roomdir/.roomstart/sessions" && -d "$sessiondir" && ! -L "$sessiondir" ]] || exit 2
sessiondir=$(cd -- "$sessiondir" && pwd -P) || exit 2
session_id=${sessiondir##*/}
[[ $session_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $sessiondir == "$roomdir/.roomstart/sessions/$session_id" ]] || exit 2
runtime="$roomdir/.roomstart/runtime"
lock="$runtime/$role.lock"
rs_runtime_regular "$lock" || exit 2
exec 9>>"$lock" || exit 2
if ! flock --nonblock --conflict-exit-code 75 9; then
    exec 8>&- 9>&-
    rs_runtime_error "$role è già aperto oppure il lock non è disponibile."
    exit 75
fi
# The launcher can transfer its launch lock until the main role lock exists.
exec 8>&-

case "$role" in
    main)
        [[ $# == 1 && -x "$1" && ! -d "$1" ]] || exit 2
        # script itself uses Bash to interpret our escaped command, but the
        # interactive user's shell must retain its own SHELL environment.
        target_command=(env "SHELL=$1" "$1" -i)
        ;;
    listener)
        [[ $# == 1 && $1 =~ ^[0-9]{1,5}$ ]] || exit 2
        (( 10#$1 >= 1 && 10#$1 <= 65535 )) || exit 2
        target_command=(nc -lvnp "$((10#$1))")
        ;;
    notes)
        [[ $# == 0 && -f "$roomdir/notes.md" && ! -L "$roomdir/notes.md" ]] || exit 2
        target_command=(nano notes.md)
        ;;
esac

for suffix in status started ended exit log; do
    rs_runtime_regular "$sessiondir/$role.$suffix" || exit 2
done
for required in setsid flock; do
    command -v "$required" >/dev/null 2>&1 || { rs_runtime_error "comando mancante: $required"; exit 69; }
done
if [[ $role != notes ]]; then
    command -v script >/dev/null 2>&1 || exit 69
fi
command -v "${target_command[0]}" >/dev/null 2>&1 || exit 69

outer_marker=$(mktemp "$runtime/$role.outer.XXXXXX") || exit 1
inner_marker=$(mktemp "$runtime/$role.inner.XXXXXX") || { rm -f -- "$outer_marker"; exit 1; }
child_pid='' child_ticks='' interrupted=false finished=false

stop_child() {
    local state parent group sid ticks attempt
    # The outer setsid helper may not have written its marker yet. A direct
    # child may be signalled only after verifying its parent and start ticks.
    if [[ -n $child_pid ]] && read -r state parent group sid ticks < <(rs_runtime_proc "$child_pid"); then
        if [[ $parent == "$$" && ( -z $child_ticks || $ticks == "$child_ticks" ) ]]; then
            kill -TERM "$child_pid" 2>/dev/null || :
        fi
    fi
    rs_runtime_signal_owned TERM "$inner_marker" "$outer_marker" || :
    for attempt in {1..30}; do
        rs_runtime_signal_owned CONT "$inner_marker" "$outer_marker" || break
        sleep 0.1
    done
    rs_runtime_signal_owned KILL "$inner_marker" "$outer_marker" || :
    if [[ -n $child_pid ]]; then
        wait "$child_pid" 2>/dev/null || :
    fi
}

finish_role() {
    local result=$1 status
    [[ $finished == false ]] || return
    finished=true
    trap '' HUP INT TERM WINCH
    stop_child
    if [[ $interrupted == true || $result == 129 || $result == 130 || $result == 143 ]]; then
        status=interrupted
    elif [[ $result == 0 ]]; then
        status=completed
    else
        status=failed
    fi
    rs_runtime_atomic "$sessiondir/$role.exit" "$result" || :
    rs_runtime_atomic "$sessiondir/$role.ended" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || :
    rs_runtime_atomic "$sessiondir/$role.status" "$status" || :
    rm -f -- "$outer_marker" "$inner_marker"
    exec 9>&-
}

on_signal() { interrupted=true; exit "$1"; }
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'rs_runtime_signal_leader "$outer_marker" WINCH || :' WINCH
trap 'finish_role "$?"' EXIT

rs_runtime_atomic "$runtime/$role.session" "$session_id" || exit 1
rs_runtime_atomic "$sessiondir/$role.started" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || exit 1
rm -f -- "$sessiondir/$role.ended" "$sessiondir/$role.exit"
rs_runtime_atomic "$sessiondir/$role.status" running || exit 1
cd -- "$roomdir" || exit 1
if [[ $role == notes ]]; then
    # Explicit stdin redirection prevents Bash replacing it with /dev/null
    # for the asynchronous child. Nano retains the terminal's input/output.
    setsid --wait bash "$SESSION_SCRIPT_DIR/session.sh" --child "$outer_marker" "${target_command[@]}" <&0 9>&- &
else
    printf -v logged_command '%q ' bash "$SESSION_SCRIPT_DIR/session.sh" --child "$inner_marker" "${target_command[@]}"
    SHELL=/bin/bash setsid --wait bash "$SESSION_SCRIPT_DIR/session.sh" --child "$outer_marker" \
        script --quiet --flush --return --append --log-out "$sessiondir/$role.log" \
        --command "exec $logged_command" <&0 9>&- &
fi
child_pid=$!
if read -r process_state process_parent process_group process_session child_ticks < <(rs_runtime_proc "$child_pid"); then :; fi
# A trapped WINCH interrupts Bash's wait even though the child is alive.
# Keep supervising that same child after a resize rather than closing it.
while :; do
    wait "$child_pid"
    result=$?
    if ((result > 128)) && jobs -pr | grep -Fxq -- "$child_pid"; then
        continue
    fi
    break
done
exit "$result"

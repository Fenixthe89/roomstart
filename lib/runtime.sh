#!/usr/bin/env bash
# Runtime state is data, never sourced as shell code. A kernel lock, rather
# than a saved PID, is the authority for whether a room tool is running.

rs_runtime_error() { printf 'Roomstart: %s\n' "$*" >&2; }

rs_runtime_role_valid() {
    case "${1:-}" in main|listener|notes) return 0 ;; *) return 1 ;; esac
}

rs_runtime_regular() {
    [[ ! -L "$1" && ( ! -e "$1" || -f "$1" ) ]]
}

rs_runtime_init() {
    local roomdir=$1 path
    [[ -d "$roomdir" && ! -L "$roomdir" ]] || return 2
    for path in "$roomdir/.roomstart" "$roomdir/.roomstart/runtime"; do
        if [[ -L "$path" || ( -e "$path" && ! -d "$path" ) ]]; then
            rs_runtime_error "percorso runtime non valido: $path"
            return 2
        fi
        (umask 077; mkdir -p -- "$path") || return 2
    done
}

rs_runtime_atomic() {
    local destination=$1 value=$2 temporary
    rs_runtime_regular "$destination" || return 2
    temporary=$(umask 077; mktemp "${destination}.tmp.XXXXXX") || return 2
    if ! printf '%s\n' "$value" > "$temporary" || ! mv -f -- "$temporary" "$destination"; then
        rm -f -- "$temporary"
        return 2
    fi
}

# Return 0 when held, 1 when free/missing, 2 on malformed state or I/O error.
rs_role_active() {
    local roomdir=$1 role=$2 lock rc
    rs_runtime_role_valid "$role" || return 2
    [[ ! -L "$roomdir/.roomstart" && ! -L "$roomdir/.roomstart/runtime" ]] || return 2
    lock="$roomdir/.roomstart/runtime/$role.lock"
    rs_runtime_regular "$lock" || return 2
    [[ -e "$lock" ]] || return 1
    if (exec 9>>"$lock" || exit 2; flock --nonblock --conflict-exit-code 75 9); then
        return 1
    else
        rc=$?
        [[ $rc == 75 ]] && return 0
        return 2
    fi
}

# Print an absolute, existing session directory for an active role.
rs_role_session() {
    local roomdir=$1 role=$2 id pointer sessionroot
    rs_role_active "$roomdir" "$role" || return $?
    pointer="$roomdir/.roomstart/runtime/$role.session"
    [[ -f "$pointer" && ! -L "$pointer" ]] || return 2
    IFS= read -r id < "$pointer" || return 2
    [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != . && $id != .. ]] || return 2
    sessionroot="$roomdir/.roomstart/sessions"
    [[ -d "$sessionroot" && ! -L "$sessionroot" && -d "$sessionroot/$id" && ! -L "$sessionroot/$id" ]] || return 2
    (cd -- "$sessionroot/$id" && pwd -P)
}

# Linux /proc identity: state, parent PID, process group, session, start ticks.
# Removing through the last ') ' handles command names containing spaces/').
rs_runtime_read_proc() {
    local pid=$1 record
    local -a fields
    [[ $pid =~ ^[1-9][0-9]*$ && -r /proc/$pid/stat ]] || return 1
    IFS= read -r record 2>/dev/null < "/proc/$pid/stat" || return 1
    read -r -a fields <<< "${record##*) }"
    [[ ${#fields[@]} -ge 20 ]] || return 1
    RS_PROC_STATE=${fields[0]} RS_PROC_PARENT=${fields[1]}
    RS_PROC_GROUP=${fields[2]} RS_PROC_SESSION=${fields[3]} RS_PROC_TICKS=${fields[19]}
}

rs_runtime_proc() {
    rs_runtime_read_proc "$1" || return 1
    printf '%s %s %s %s %s\n' "$RS_PROC_STATE" "$RS_PROC_PARENT" "$RS_PROC_GROUP" "$RS_PROC_SESSION" "$RS_PROC_TICKS"
}

# Markers are newly allocated by this wrapper, never reused from an old run.
# A Linux session ID stays reserved while members exist, even after its leader
# exits. If the leader still exists, its start time must match the marker.
rs_runtime_owned_session() {
    local marker=$1 pid ticks sid state parent group current_sid current_ticks
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    read -r pid ticks sid < "$marker" || return 1
    [[ $pid =~ ^[1-9][0-9]*$ && $ticks =~ ^[0-9]+$ && $sid == "$pid" ]] || return 1
    if read -r state parent group current_sid current_ticks < <(rs_runtime_proc "$pid"); then
        [[ $current_ticks == "$ticks" && $current_sid == "$sid" ]] || return 1
    fi
    printf '%s\n' "$sid"
}

# The outer supervisor receives the original terminal's resize signal and
# forwards it to script (or nano), which updates its own screen/PTY dimensions.
rs_runtime_signal_leader() {
    local marker=$1 signal=$2 pid ticks sid
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    read -r pid ticks sid < "$marker" || return 1
    rs_runtime_read_proc "$pid" || return 1
    [[ $pid == "$sid" && $RS_PROC_TICKS == "$ticks" && $RS_PROC_SESSION == "$sid" ]] || return 1
    kill -s "$signal" -- "$pid" 2>/dev/null
}

# Signal only processes in sessions created for this role. Interactive shells
# create additional job-control groups; signal each one, not the caller's group.
rs_runtime_signal_owned() {
    local signal=$1; shift
    local marker sid statfile pid state parent group current_sid ticks
    local -A groups=()
    for marker in "$@"; do
        sid=$(rs_runtime_owned_session "$marker") || continue
        for statfile in /proc/[0-9]*/stat; do
            pid=${statfile#/proc/}; pid=${pid%/stat}
            rs_runtime_read_proc "$pid" || continue
            [[ $RS_PROC_SESSION == "$sid" && $RS_PROC_STATE != Z && $RS_PROC_GROUP =~ ^[1-9][0-9]*$ ]] || continue
            groups[$RS_PROC_GROUP]=1
        done
    done
    for group in "${!groups[@]}"; do
        kill -s "$signal" -- "-$group" 2>/dev/null || :
    done
    [[ ${#groups[@]} -gt 0 ]]
}

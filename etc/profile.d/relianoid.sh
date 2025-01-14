#!/bin/bash

export PATH="${PATH}:/usr/local/relianoid/bin"

# If not using bash, it's most likely the load balancer is running a command 
# with environment variables
[ -z "$BASH_VERSION" ] && return

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

CLUSTER_STATUS=/etc/relianoid-ce-cluster.status

function cluster_node {
    [ -f $CLUSTER_STATUS ] && echo -n "[$(cat $CLUSTER_STATUS 2>/dev/null)] "
}

# set a fancy prompt (non-color, overwrite the one in /etc/profile)
# but only if not SUDOing and have SUDO_PS1 set; then assume smart user.
if ! [ -n "${SUDO_USER}" -a -n "${SUDO_PS1}" ]; then
    PS1='${debian_chroot:+($debian_chroot)}$(cluster_node)\u@\h:\w\$ '
fi

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
   PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"'
   ;;
*)
   ;;
esac


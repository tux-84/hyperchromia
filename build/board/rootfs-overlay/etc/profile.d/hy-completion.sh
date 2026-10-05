#!/bin/bash
[[ $- == *i* ]] || return 0

complete -W "help restart net netconfig reboot poweroff backup restore upgrade factoryreset password mqtt locale status" hy

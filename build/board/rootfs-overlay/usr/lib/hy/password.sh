#!/bin/bash
hy_cmd_password() {
	if [ "$HY_PRESEED_ACTIVE" = "1" ]; then
		if [ -n "$HY_PRESEED_ROOT_PASSWORD" ]; then
			echo "root:$HY_PRESEED_ROOT_PASSWORD" | chpasswd
		fi
		return 0
	fi

	echo "Changing the root password."
	passwd root
}

#!/usr/bin/expect

set timeout 120

set ADMINUSER "$::env(NETBIOS_NAME)\\$::env(ADMINUSER)"
set PASSWD "$::env(ADMINPASSWORD)"
set HOST "$::env(VM_INT_IP)"
spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l $ADMINUSER $HOST

expect {
	"password:" { send "${PASSWD}\r"; exp_continue }
	">" { send "dir C:\\\r" }
}
expect -re "administrator.*>" {
	puts $expect_out(buffer)
}

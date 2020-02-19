#!/usr/bin/expect

set timeout 120

set ADMINUSER "$::env(ADMINUSER)"
set PASSWD "$::env(ADMINPASSWORD)"
set HOST "$::env(VM_INT_IP)"
spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l $ADMINUSER $HOST

set pprefix [string tolower ${ADMINUSER}@]
expect {
	"password:" { send "${PASSWD}\r"; exp_continue }
	-re "${pprefix}.*>" { send "dir C:\\ & type C:\\ipconfig.log\r & type C:\\postinstall.log\r" }
}
expect -re "${pprefix}.*>" {
	puts ""
}

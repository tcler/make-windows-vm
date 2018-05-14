#!/usr/bin/expect

set timeout 120

set NETBIOSNAME "$::env(NETBIOS_NAME)"
set ADMINUSER "$::env(ADMINUSER)"
set LOGINUSER "${NETBIOSNAME}\\${ADMINUSER}"
set PASSWD "$::env(ADMINPASSWORD)"
set HOST "$::env(VM_INT_IP)"
spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l $LOGINUSER $HOST

set pprefix [string tolower ${ADMINUSER}@${NETBIOSNAME}@]
expect {
	"password:" { send "${PASSWD}\r"; exp_continue }
	-re "${pprefix}.*>" { send "dir C:\\\r" }
}
expect -re "${pprefix}.*>" {
	puts ""
}

#!/bin/bash

# test AD connection and get AD CA cert
get_cert() {
	local vmname=$1
	local fqdn=$2
	local domain=$3
	local user=${4%:*}
	local passwd=${4#*:}
	local ldapurl=$5

	local ldapreqcert=never
	local lmhn=${fqdn%%.*}
	local lmdn=${domain%%.*}
	local ca_name="$lmdn-$lmhn-ca"
	local ad_suffix="dc=${domain//./,dc=}"
	local ca_cert_dn="cn=$ca_name,cn=certification authorities,cn=public key services,cn=services,cn=configuration,$ad_suffix"
	local tmp_cacert=/tmp/cacert.$(date +%Y%m%d%H%M%S).$$.pem
	local win_ca_cert_file=/tmp/$vmname.crt
	local admin_dn="cn=$user,cn=users,$ad_suffix"

	local data=
	until data=$(ldapsearch -xLLL -H $ldapurl -D "$admin_dn" -w "$passwd" -s base -b "$ca_cert_dn" "objectclass=*" cACertificate); do sleep 1; done
	{
		echo "-----BEGIN CERTIFICATE-----"
		echo "$data" | xargs | sed -r -e 's/.*cACertificate:: //' -e 's/ //g;' -e 's/(.{64})/\1\n/g;'
		echo "-----END CERTIFICATE-----"
	} >$tmp_cacert
	cat $tmp_cacert
	echo Now test our CA cert

	export LDAPTLS_CACERT=$tmp_cacert
	export LDAPTLS_REQCERT=$ldapreqcert
	if ldapsearch -xLLL -ZZ -H $ldapurl -D "$admin_dn" -w "$passwd" -s base -b "" "objectclass=*" currenttime > /dev/null 2>&1; then
		echo Success - the CA cert in $tmp_cacert is working
	else
		echo Error: the CA cert in $tmp_cacert is not working
		ldapsearch -d 1 -xLLL -ZZ -H $ldapurl -s base -b "" "objectclass=*" currenttime
	fi  
	\cp -p $tmp_cacert $win_ca_cert_file
	\rm -f $tmp_cacert
}
get_cert "$@"

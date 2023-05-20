#!/usr/bin/env bash

set -euo pipefail

tmp=$(mktemp -d --suffix=client-krb)
trap 'rm -rf $tmp' EXIT

echo "tmp dir: $tmp"

export KRB5_CONFIG=$tmp/krb5.conf
export KRB5CCNAME=$tmp/krbcc

cat >"$KRB5_CONFIG" <<EOF
[libdefaults]
	default_realm = KRB.TEST

[realms]
	KRB.TEST = {
		admin_server = localhost:4749
		kdc = localhost:4488
	}
EOF

kdestroy -q || true
echo 'alice_pw' | kinit alice

exec $@

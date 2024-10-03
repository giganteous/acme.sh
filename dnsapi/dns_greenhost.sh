#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_greenhost_info='greenhost.net
Site: greenhost.nl
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_greenhost
Options:
 Greenhost_Key API Key
Author: <kai@xs4all.nl>
'
# Thanks for the examples for digital ocean, nederhost and cloudflare

Greenhost_Api="https://service.greenhost.net/api/v2"

#####################  Public functions  #####################
#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_greenhost_add() {
  fulldomain=$1
  txtvalue=$2

  _greenhost_getkey || return 1

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "domain not found in your account for addition"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  # shellcheck disable=SC2086
  if _greenhost_rest POST "domains/${_domain}/records" '{"type":"TXT","name":"'${_sub_domain}'","data":"\"'${txtvalue}'\"","ttl":60}'; then
    if [ "$_code" = "201" ]; then
      _info "Added, OK"
      return 0
    fi
  fi

  _err "Add txt record error."
  return 1
}

## Remove the txt record after validation. we saved the record id
dns_greenhost_rm() {
  fulldomain=$1
  txtvalue=$2

  _greenhost_getkey || return 1

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "domain not found in your account for addition"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Removing record"
  if _greenhost_rest GET "domains/${_domain}/records"; then
    record="$(echo "$response" | _egrep_o "\"id\"[^}]*${_sub_domain}\"[^}]*${txtvalue}")"
    if [ -n "$record" ]; then
      id="$(echo "$record" | _egrep_o "id\"\s*\:\s*\"*[0-9]+" | _egrep_o "[0-9]+")"
      if _greenhost_rest DELETE "domains/${_domain}/records/${id}"; then
        if [ "$_code" = "204" ]; then
          _info "Removed, OK"
          return 0
        fi
        _info "Delete failed, someone should cleanup"
        return 0
      fi
    fi
    _info "No records found, weird, but OK"
    return 0
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    _domain=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
    _debug _domain "$_domain"
    if [ -z "$_domain" ]; then
      #not valid
      return 1
    fi

    if _greenhost_rest GET "domains/${_domain}/records"; then
      if [ "${_code}" = "200" ]; then
        return 0
      fi
    else
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#"HTTPMETHOD" "sub/path" "optional post data"
#returns
# _code=http result code
# response=http body
_greenhost_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  _debug data "$data"
  response="$(_post "$data" "$Greenhost_Api/$ep" "" "$m")"

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_greenhost_getkey() {
  Greenhost_Key="${Greenhost_Key:-$(_readaccountconf_mutable Greenhost_Key)}"
  # Check if API Key Exists
  if [ -z "${Greenhost_Key}" ]; then
    Greenhost_Key=""
    _err "No Greenhost_Key; Create it on https://service.greenhost.net/administration"
    _err "(navigate to your account settings then select the api keys tab)"
    return 1
  fi

  ## save the key
  _saveaccountconf_mutable Greenhost_Key "$Greenhost_Key"
  export _H1="Authorization: Bearer $Greenhost_Key"
  export _H2="Content-Type: application/json"
  return 0
}

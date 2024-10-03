#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_greenhost_info='greenhost.net
Site: https://service.greenhost.net/apidocs#/default
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_greenhost
Options:
 GH_API_KEY API Key
Author: <kai@xs4all.nl>
'

#####################  Public functions  #####################

## Create the text record for validation.
## Usage: fulldomain txtvalue
## EG: "_acme-challenge.www.other.domain.com" "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_greenhost_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  GH_API_KEY="${GH_API_KEY:-$(_readaccountconf_mutable GH_API_KEY)}"
  # Check if API Key Exists
  if [ -z "$GH_API_KEY" ]; then
    GH_API_KEY=""
    _err "You did not specify Greenhost API key."
    _err "Please export GH_API_KEY and try again."
    return 1
  fi

  _info "Using greenhost.nl dns validation - add record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## save the env vars (key and domain split location) for later automated use
  _saveaccountconf_mutable GH_API_KEY "$GH_API_KEY"

  ## split the domain for DO API
  if ! _get_root "$fulldomain"; then
    _err "domain not found in your account for addition"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  ## Set the header with our post type and key auth key
  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $GH_API_KEY"
  PURL='https://service.greenhost.net/api/v2/domains/'$_domain'/records'
  PBODY='{"type":"TXT","name":"'$_sub_domain'","data":"'$txtvalue'","ttl":120}'

  _debug PURL "$PURL"
  _debug PBODY "$PBODY"

  ## the create request - post
  ## args: BODY, URL, [need64, httpmethod]
  response="$(_post "$PBODY" "$PURL")"

  ## check response
  if [ "$?" != "0" ]; then
    _err "error in response: $response"
    return 1
  fi
  _debug2 response "$response"

  ## finished correctly
  return 0
}

## Remove the txt record after validation.
## Usage: fulldomain txtvalue
## EG: "_acme-challenge.www.other.domain.com" "XKrxpRBosdq0HG9i01zxXp5CPBs"
dns_greenhost_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  GH_API_KEY="${GH_API_KEY:-$(_readaccountconf_mutable GH_API_KEY)}"
  # Check if API Key Exists
  if [ -z "$GH_API_KEY" ]; then
    GH_API_KEY=""
    _err "You did not specify Greenhost API key."
    _err "Please export GH_API_KEY and try again."
    return 1
  fi

  _info "Using Greenhost dns validation - remove record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## split the domain for DO API
  if ! _get_root "$fulldomain"; then
    _err "domain not found in your account for removal"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  ## Set the header with our post type and key auth key
  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $GH_API_KEY"
  ## get URL for the list of domains
  GURL="https://service.greenhost.net/api/v2/domains/$_domain/records"

  ## Get all the matching records
  while true; do
    ## 1) get the URL
    ## the create request - get
    ## args: URL, [onlyheader, timeout]
    record_list="$(_get "$GURL")"

    ## check response
    if [ "$?" != "0" ]; then
      _err "error in record_list response: $record_list"
      return 1
    fi
    _debug2 record_list "$record_list"

    ## 2) find records
    ## check for what we are looking for: "type":"A","name":"$_sub_domain"
    record="$(echo "$record_list" | _egrep_o "\"id\"\s*\:\s*\"*[0-9]+\"*[^}]*\"name\"\s*\:\s*\"$_sub_domain\"[^}]*$txtvalue")"

    if [ -n "$record" ]; then

      ## we found records
      rec_ids="$(echo "$record" | _egrep_o "id\"\s*\:\s*\"*[0-9]+" | _egrep_o "[0-9]+")"
      _debug rec_ids "$rec_ids"
      if [ -n "$rec_ids" ]; then
        echo "$rec_ids" | while IFS= read -r rec_id; do
          ## delete the record
          ## delete URL for removing the one we dont want
          DURL="https://service.greenhost.net/api/v2/domains/$_domain/records/$rec_id"

          ## the create request - delete
          ## args: BODY, URL, [need64, httpmethod]
          response="$(_post "" "$DURL" "" "DELETE")"

          ## check response (sort of)
          if [ "$?" != "0" ]; then
            _err "error in remove response: $response"
            return 1
          fi
          _debug2 response "$response"
          return 0
        done
      fi
    fi

    ## Greenhost does not offer next page support.
    return 1
  done

  ## finished correctly
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  DOMURL="https://service.greenhost.net/api/v2/domains"
  i=2
  p=1
  while true; do
    _domain=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
    _debug _domain "$_domain"
    if [ -z "$_domain" ]; then
      return 1
    fi

    if _get "$DOMURL/${_domain}/records"; then
      _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
      _debug "http response code $_code"
      if [ "${_code}" = "200" ]; then
        _debug _domain $_domain
        _debug _sub_domain $_sub_domain
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

_get_with_rcode() {
  url=$1
  _debug "$url"

  response="$(_get "$url")"

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

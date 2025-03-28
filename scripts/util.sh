#!/bin/bash

userAgent="GitHub Autodeploy Bot/1.1.0 (${WIKI_UA_EMAIL})"

declare -A loggedin
declare -a protectErrors=()

login() {
  wiki=$1

  if [[ ${loggedin[${wiki}]} != 1 ]]; then
    ckf="cookie_${wiki}.ck"
    wikiApiUrl="${WIKI_BASE_URL}/${wiki}/api.php"
    echo "...logging in on \"${wiki}\""
    loginToken=$(
      curl \
        -s \
        -b "$ckf" \
        -c "$ckf" \
        -d "format=json&action=query&meta=tokens&type=login" \
        -H "User-Agent: ${userAgent}" \
        -H 'Accept-Encoding: gzip' \
        -X POST "$wikiApiUrl" \
        | gunzip \
        | jq ".query.tokens.logintoken" -r
    )
    curl \
      -s \
      -b "$ckf" \
      -c "$ckf" \
      --data-urlencode "lgname=${WIKI_USER}" \
      --data-urlencode "lgpassword=${WIKI_PASSWORD}" \
      --data-urlencode "lgtoken=${loginToken}" \
      -H "User-Agent: ${userAgent}" \
      -H 'Accept-Encoding: gzip' \
      -X POST "${wikiApiUrl}?format=json&action=login" \
      | gunzip \
      > /dev/null
    loggedin[$wiki]=1
    # Don't get rate limited
    sleep 4
  fi
}

getToken(){
  wiki=$1
  wikiApiUrl="${WIKI_BASE_URL}/${wiki}/api.php"
  ckf="cookie_${wiki}.ck"

  login $wiki

  token=$(
    curl \
      -s \
      -b "$ckf" \
      -c "$ckf" \
      -d "format=json&action=query&meta=tokens" \
      -H "User-Agent: ${userAgent}" \
      -H 'Accept-Encoding: gzip' \
      -X POST "$wikiApiUrl" \
      | gunzip \
      | jq ".query.tokens.csrftoken" -r
  )
}

protectPage() {
  page="${1}"
  wiki=$2
  protectOptions=$3
  protectMode=$4
  echo "...wiki = $wiki"
  echo "...page = ${page}"
  wikiApiUrl="${WIKI_BASE_URL}/${wiki}/api.php"
  ckf="cookie_${wiki}.ck"

  getToken $wiki

  rawProtectResult=$(
    curl \
      -s \
      -b "$ckf" \
      -c "$ckf" \
      --data-urlencode "title=${page}" \
      --data-urlencode "protections=${protectOptions}" \
      --data-urlencode "reason=Git maintained" \
      --data-urlencode "expiry=infinite" \
      --data-urlencode "bot=true" \
      --data-urlencode "token=${token}" \
      -H "User-Agent: ${userAgent}" \
      -H 'Accept-Encoding: gzip' \
      -X POST "${wikiApiUrl}?format=json&action=protect" \
      | gunzip
  )
  # Don't get rate limited
  sleep 4

  result=$(echo "$rawProtectResult" | jq ".protect.protections.[].${protectMode}" -r)
  if [[ $result != *"allow-only-sysop"* ]]; then
    echo "::warning::could not (${protectMode}) protect ${page} on ${wiki}"
    protectErrorMsg="${protectMode}:${wiki}:${page}"
    protectErrors+=("${protectErrorMsg}")
  fi
}

checkIfPageExists() {
  page="${1}"
  wiki="${2}"
  wikiApiUrl="${WIKI_BASE_URL}/${wiki}/api.php"
  ckf="cookie_${wiki}.ck"

  rawResult=$(
    curl \
      -s \
      -b "$ckf" \
      -c "$ckf" \
      --data-urlencode "titles=${page}" \
      --data-urlencode "prop=info" \
      -H "User-Agent: ${userAgent}" \
      -H 'Accept-Encoding: gzip' \
      -X POST "${wikiApiUrl}?format=json&action=query" \
      | gunzip
  )

  # Don't get rate limited
  sleep 4

  if [[ $rawResult == *'missing":"'* ]]; then
    pageExists=false
  else
    pageExists=true
  fi
}

protectNonExistingPage() {
  page="${1}"
  wiki=$2

  checkIfPageExists "${page}" $wiki
  if $pageExists; then
    echo "::warning::$page already exists on $wiki"
    protectErrors+=("create:${WIKI_TO_PROTECT}:${page}")
  else
    protectPage "${page}" "${wiki}" "create=allow-only-sysop" "create"
  fi

}

protectExistingPage() {
  protectPage "${1}" "${2}" "edit=allow-only-sysop|move=allow-only-sysop" "edit"
}

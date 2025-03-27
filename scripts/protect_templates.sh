#!/bin/bash

userAgent="GitHub Autodeploy Bot/1.1.0 (${WIKI_UA_EMAIL})"

. /scripts/util.sh

declare -A loggedin
declare -a protectErrors=()

readarray filesToProtect < "./templates/templatesToProtect"

protectPage() {
  page="${1}"
  wiki=$2
  protectOptions=$3
  protectMode=$4
  echo "...wiki = $wiki"
  echo "...page = ${page}"
  wikiApiUrl="${WIKI_BASE_URL}/${wiki}/api.php"
  ckf="cookie_${wiki}.ck"

  editOrProtectToken=$(loginAndGetToken $wiki)
  echo "... ${editOrProtectToken}"
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
      --data-urlencode "token=${editOrProtectToken}" \
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

protectExistingPage() {
  protectPage "${1}" "${2}" "edit=allow-only-sysop|move=allow-only-sysop" "edit"
}

protectNonExistingPage() {
  protectPage "${1}" "${2}" "create=allow-only-sysop" "create"
}

checkIfPageExists() {
  page="${1}"
  wikiApiUrl="${WIKI_BASE_URL}/${2}/api.php"
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

  if [[ $rawResult == *'missing'* ]]; then
    pageExists=false
  else
    pageExists=true
  fi
}

for fileToProtect in "${filesToProtect[@]}"; do
  echo "::group::Trying to protect for $fileToProtect"
  template="Template:${fileToProtect}"
  if [[ "commons" == ${WIKI_TO_PROTECT} ]]; then
    protectExistingPage $template ${WIKI_TO_PROTECT}
  else
    checkIfPageExists "${template}" $deployWiki
    if $pageExists; then
      echo "::warning::$fileToProtect already exists on $deployWiki"
      protectErrors+=("create:${WIKI_TO_PROTECT}:${fileToProtect}")
    else
      protectNonExistingPage "${template}" ${WIKI_TO_PROTECT}
    fi
  fi
  echo '::endgroup::'
done

if [[ ${#regexErrors[@]} -ne 0 ]]; then
  echo "::warning::Some regexes failed"
  echo ":warning: Some regexes failed" >> $GITHUB_STEP_SUMMARY
  echo "::group::Files the regex failed on"
  for value in "${regexErrors[@]}"; do
     echo "... ${failedRegex}"
  done
  echo "::endgroup::"
fi

if [[ ${#protectErrors[@]} -ne 0 ]]; then
  echo "::warning::Some templates could not be protected"
  echo ":warning: Some templates could not be protected" >> $GITHUB_STEP_SUMMARY
  echo "::group::Failed protections"
  for value in "${protectErrors[@]}"; do
     echo "... ${value}"
  done
  echo "::endgroup::"
fi

rm -f cookie_*

if [[ ${#protectErrors[@]} -ne 0 ]] || [[ ${#regexErrors[@]} -ne 0 ]]; then
  exit 1
fi

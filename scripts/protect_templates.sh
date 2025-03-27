#!/bin/bash

userAgent="GitHub Autodeploy Bot/1.1.0 (${WIKI_UA_EMAIL})"

declare -a protectErrors=()

. ./util.sh

readarray filesToProtect < "./templates/templatesToProtect"

for fileToProtect in "${filesToProtect[@]}"; do
  echo "::group::Trying to protect for $fileToProtect"
  template="Template:${fileToProtect}"
  if [[ "commons" == ${WIKI_TO_PROTECT} ]]; then
    protectExistingPage $template ${WIKI_TO_PROTECT}
  else
    protectNonExistingPage "${template}" ${WIKI_TO_PROTECT}
  fi
  echo '::endgroup::'
done

rm -f cookie_*

if [[ ${#protectErrors[@]} -ne 0 ]]; then
  echo "::warning::Some templates could not be protected"
  echo ":warning: Some templates could not be protected" >> $GITHUB_STEP_SUMMARY
  echo "::group::Failed protections"
  for value in "${protectErrors[@]}"; do
     echo "... ${value}"
  done
  echo "::endgroup::"
  exit 1
fi

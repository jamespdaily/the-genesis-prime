#!/usr/bin/env bash
# Files and moves cards on the project board, so no one looks up the board's ids.
#
#   dev/card.sh file --title T --body-file F --milestone M --parent N --after S --status STATUS
#   dev/card.sh status N STATUS
#   dev/card.sh move N --parent P [--after S]
#   dev/card.sh order N --after S
#
# STATUS is one of: "To do", "In progress", "Waiting on Jim", "Done".
# N, P and S are issue numbers; S is the sibling the card goes right after.
set -euo pipefail

owner=jamespdaily
repo=the-genesis-prime
project_number=2
project_id=PVT_kwHOAAdMUc4BopzC
status_field=PVTSSF_lAHOAAdMUc4BopzCzhnI34c

fail() { echo "card: $*" >&2; exit 1; }

option_of() {
  case "$1" in
    "To do") echo 6f9a1733 ;;
    "In progress") echo b6834e8c ;;
    "Waiting on Jim") echo eae5e8ae ;;
    "Done") echo 03a70090 ;;
    *) fail "unknown status '$1'" ;;
  esac
}

# issue_field N JQ: one field of issue N (id, parent number, board item).
issue_field() {
  gh api graphql -f query="query{repository(owner:\"$owner\",name:\"$repo\"){issue(number:$1){id parent{number id} projectItems(first:10){nodes{id project{number}}}}}}" \
    --jq ".data.repository.issue | $2"
}

node_id() { issue_field "$1" '.id'; }
parent_number() { issue_field "$1" '.parent.number // empty'; }
board_item() { issue_field "$1" "[.projectItems.nodes[] | select(.project.number == $project_number) | .id][0] // empty"; }

# require_sibling P S: fails unless S is a sub-issue of P (every page is read).
require_sibling() {
  local found
  found=$(gh api graphql --paginate -f query="query(\$endCursor:String){repository(owner:\"$owner\",name:\"$repo\"){issue(number:$1){subIssues(first:100,after:\$endCursor){nodes{number} pageInfo{hasNextPage endCursor}}}}}" \
    --jq ".data.repository.issue.subIssues.nodes[] | select(.number == $2) | .number")
  [ -n "$found" ] || fail "#$2 is not a sub-issue of #$1"
}

mutate() { gh api graphql -f query="mutation{$1}" >/dev/null; }

add_under() { mutate "addSubIssue(input:{issueId:\"$(node_id "$2")\",subIssueId:\"$(node_id "$1")\"}){issue{number}}"; }
remove_from() { mutate "removeSubIssue(input:{issueId:\"$(node_id "$2")\",subIssueId:\"$(node_id "$1")\"}){issue{number}}"; }
place_after() { mutate "reprioritizeSubIssue(input:{issueId:\"$(node_id "$2")\",subIssueId:\"$(node_id "$1")\",afterId:\"$(node_id "$3")\"}){issue{number}}"; }

set_status() {
  local option item tries=0
  option=$(option_of "$2")
  item=$(board_item "$1")
  # A new issue reaches the board a moment after it is created.
  while [ -z "$item" ] && [ $tries -lt 10 ]; do
    sleep 1; tries=$((tries + 1)); item=$(board_item "$1")
  done
  [ -n "$item" ] || fail "#$1 is not on the board"
  gh project item-edit --id "$item" --project-id "$project_id" --field-id "$status_field" \
    --single-select-option-id "$option" >/dev/null
}

command=${1:-}; shift || true
case "$command" in
  file)
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) title=$2 ;; --body-file) body=$2 ;; --milestone) milestone=$2 ;;
        --parent) parent=$2 ;; --after) after=$2 ;; --status) status=$2 ;;
        *) fail "unknown option $1" ;;
      esac
      shift 2
    done
    : "${title:?--title}" "${body:?--body-file}" "${milestone:?--milestone}" "${parent:?--parent}" "${after:?--after}" "${status:?--status}"
    [ -f "$body" ] || fail "no body file $body"
    option_of "$status" >/dev/null
    require_sibling "$parent" "$after"
    existing=$(gh issue list -R "$owner/$repo" --state open --search "in:title $title" --json number,title \
      --jq ".[] | select(.title == \"$title\") | .number")
    [ -z "$existing" ] || fail "an open issue already has this title: #$existing"
    url=$(gh issue create -R "$owner/$repo" --title "$title" --milestone "$milestone" --body-file "$body")
    number=${url##*/}
    step=add-to-parent
    trap 'echo "card: #$number was created; not done from: $step" >&2' ERR
    add_under "$number" "$parent"
    step=order; place_after "$number" "$parent" "$after"
    step=status; set_status "$number" "$status"
    trap - ERR
    echo "$url"
    ;;
  status)
    [ $# -eq 2 ] || fail "usage: card.sh status N STATUS"
    set_status "$1" "$2"
    ;;
  move)
    number=$1; shift
    after=""
    while [ $# -gt 0 ]; do
      case "$1" in --parent) parent=$2 ;; --after) after=$2 ;; *) fail "unknown option $1" ;; esac
      shift 2
    done
    : "${parent:?--parent}"
    [ -z "$after" ] || require_sibling "$parent" "$after"
    old=$(parent_number "$number")
    if [ -n "$old" ] && [ "$old" != "$parent" ]; then remove_from "$number" "$old"; fi
    [ "$old" = "$parent" ] || add_under "$number" "$parent"
    [ -z "$after" ] || place_after "$number" "$parent" "$after"
    ;;
  order)
    [ $# -eq 3 ] && [ "$2" = --after ] || fail "usage: card.sh order N --after S"
    parent=$(parent_number "$1")
    [ -n "$parent" ] || fail "#$1 has no parent"
    require_sibling "$parent" "$3"
    place_after "$1" "$parent" "$3"
    ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac

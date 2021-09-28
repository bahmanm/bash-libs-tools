################################################################################
# bash-libs-tools/main.sh
#
# a collection of tools and libs for bash.
#
# - simply `source main.sh` to use.
# - related functions are grouped into so-called packages which prefix a
#   function's name, eg "git.update_repo" is in package "git".
# - currently functions do not have "help" switch but are, i think, decently
#   documented where it made sense.
# - currently a big body of code - can be broken into smaller pieces in the
#   if the need arises.
################################################################################

set -o nounset

################################################################################
### bash builtins override
################################################################################

function pushd {
  command pushd "$@" > /dev/null
}

function popd {
  command popd "$@" > /dev/null
}

################################################################################
### package _
################################################################################

###############
# _.error(msg)
# outputs: `msg` on `stdout`
# returns: 0
###############
function _.error {
  echo "$1" >& 2
}

###############
# _.sig(re, sig=15, not_re='')
# sends `sig` signal to process whose cmd match `re` and not match `not_re`.
# outputs: none
# returns: 0
###############
function _.sig {
  local re not_re sig perl_cmd

  re="${1:-\$^}"
  sig="${2:-15}"
  not_re="${3:-\$^}"
  perl_cmd=$(cat <<EOF
    if (\$F[10] =~ /$re/ && \$F[10] !~ /$not_re/ && \$F[1] ne "\$\$") {
      print \$F[1]
    }
EOF
          )
  ps aux \
    | perl -nalE "$perl_cmd" \
    | xargs -r kill -"$sig"
}

################################################################################
### package git
################################################################################

###############
# git.update_repo(repo, stash_uncommitted=true)
# output: n/a
# returns: 0 if successful (or no remote tracking ref)
# fetches all the remotes, stashes any uncommitted index work, and resets
# the HEAD to the tip of the current tracking ref.
###############
function git.update_repo {
  local repo tracking_ref stash_uncommitted

  repo="$1"
  pushd "$repo"
  tracking_ref=$(git._tracking_ref "$repo") || return 0
  stash_uncommitted=[[ "${2:-true}" == 'true' ]]
  if git.has_uncommitted "$repo" && $stash_uncommitted; then
    git stash push -q
  fi
  git fetch -q --all > /dev/null \
    && git reset -q --hard "$tracking_ref" > /dev/null || exit 1
  popd
}

###############
# git._tracking_ref(repo)
# output: tracking branch or empty
# returns: 0 if branch tracked, 1 otherwise
###############
function git._tracking_ref {
  local repo result

  repo="$1"
  pushd "$repo"
  result=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
  if (( $? == 0)); then
    echo "$result"
  else
    return 1
  fi
}

###############
# git.has_uncommitted(repo)
# returns: 0 if `repo` has uncommitted changes, non-zero otherwise.
#          exits w/ 1 in case of failure
# output: n/a
###############
function git.has_uncommitted {
  local repo result

  repo="$1"
  pushd "$repo"
  result=$(git status --short | wc -l) || exit 1
  popd
  if (( $result > 0 )); then
    return 0
  else
    return 1
  fi
}

################################################################################
### package ws
###
# sample ws (json)
# {
#   "dirs": {
#     "/path/to/dir/1": {
#       "includes": "\\.java$|\\.scala$",
#       "excludes": ".*Fixtures\\.java$|.*Resource\\.scala"
#     }
#   },
#   "tagfile": "/path/to/some/arbitrary/dir/tags",
#   "root": "/path/to/some/arbitrary/dir"
# }
################################################################################

WS_DB_HOME="$HOME/.config/bahman/ws"

###############
# ws._get_tagfile(ws)
# returns: exits w/ 1 if ws does not exists, 0 otherwise
# outputs: tagfile path
###############
function ws._get_tagfile {
  local ws result

  ws=$(ws._abspath "$1")
  result=$(jq -er '.tagfile' < "$ws") || exit 1
  echo "$result"
}

###############
# ws._get_root(ws)
# returns: exits w/ 1 if ws does not exists, 0 otherwise
# outputs: root path
###############
function ws._get_root {
  local ws result

  ws=$(ws._abspath "$1")
  result=$(jq -er '.root' < "$ws") || exit 1
  echo "$result"
}

###############
# ws._get_dirs(ws, as_json=false)
# returns: exits w/ 1 if ws does not exists, 0 otherwise
# outputs: dirs
###############
function ws._get_dirs {
  local ws as_json result

  ws=$(ws._abspath "$1") && ws.verify_exists "$ws"
  as_json="${2:-false}"
  if [[ "$as_json" == 'false' ]]; then
    result=$(jq -er '.dirs | keys[]' < "$ws") || exit 1
  else
    result=$(jq -er '.dirs | keys' < "$ws") || exit 1
  fi
  echo "$result"
}

###############
# ws._get_dir(ws, dir)
# returns: exits w/ 1 if ws/dir does not exists, 0 otherwise
# outputs: dir as json
###############
function ws._get_dir {
  local ws dir result

  ws=$(ws._abspath "$1") && ws.verify_exists "$ws"
  dir="$2"
  result=$(jq -er ".dirs.\"$dir\"" < "$ws") || exit 1
  echo "$result"
}

###############
# ws.dir._get_includes(dir)
# returns: exits w/ 1 if ws does not exists, 0 otherwise
# outputs: includes
###############
function ws.dir._get_includes {
  local dir result
  dir="$1"
  result=$(echo "$1" | jq -er '.includes') || exit 1
  echo "$result"
}

###############
# ws.dir._get_excludes(dir)
# returns: exits w/ 1 if ws does not exists, 0 otherwise
# outputs: excludes
###############
function ws.dir._get_excludes {
  local dir result
  dir="$1"
  result=$(echo "$1" | jq -er '.excludes') || exit 1
  echo "$result"
}

###############
# ws._abspath(ws)
# output: full path to `ws`
# returns: 0
###############
function ws._abspath {
  if [[ "$1" == $WS_DB_HOME/* ]]; then
    echo "$1"
  else
    echo "$WS_DB_HOME/$1"
  fi
}

###############
# ws._delete(ws)
# returns: 0
###############
function ws.delete {
  local ws=$(ws._abspath "$1")
  rm -f "$ws"
}

###############
# ws.create(ws, root, tagfile)
# output: n/a
# returns: 0
###############
function ws.create {
  local ws=$(ws._abspath "$1")
  local root=$(readlink -f "${2:-$(pwd)}")
  local tagfile="$root/${3:-TAGS}"
  if [[ ! -d "$root" ]]; then
    mkdir -p $"root"
  fi
  if [[ ! -f "$ws" ]]; then
    echo '{}' \
      | jq -r ".id = \"$1\"" \
      | jq -r ".dirs = {}" \
      | jq -r ".tagfile = \"$tagfile\"" \
      | jq -r ".root = \"$root\"" > "$ws"
  fi
}

###############
# ws.verify_exists(ws)
# output: error message if does not exist
# returns: 0 if exists, exits w/ 1 otherwise
###############
function ws.verify_exists {
  local ws=$(ws._abspath "$1")
  if [[ ! -f "$ws" ]]; then
    echo "missing workspace - use `ws.create`" >&2
    exit 1
  fi
}

###############
# ws.dirs._add(ws, dir, includes='.*', excludes='^$')
# output: n/a
# returns: 0
###############
function ws.dirs._add {
  local ws includes excludes dir tmp_ws

  ws=$(ws._abspath "$1") &&  ws.verify_exists "$1"
  includes="${3:-.*}"
  excludes="${4:-^$}"
  dir=$(readlink -f "$2")
  tmp_ws=$(mktemp)
  { jq -r ".dirs.\"$dir\" = {}" < "$ws" \
      | jq -r ".dirs.\"$dir\".includes = \"$includes\"" \
      | jq -r ".dirs.\"$dir\".excludes = \"$excludes\"" > "$tmp_ws"; } \
    && cp -f "$ws" "$ws.backup" \
    && mv "$tmp_ws" "$ws"
}

###############
# ws.generate_tags(ws)
# (re-)generate the ws tags file
# returns: 0
# outputs: n/a
###############
function ws.generate_tags {
  local ws tagfile dirs dir_data includes excludes

  ws="$1"
  dirs=$(ws._get_dirs "$ws")
  tagfile=$(ws._get_tagfile "$ws")
  if [[ -f "$tagfile" ]]; then
    mv "$tagfile" "$tagfile.backup"
  fi
  for dir in $dirs; do
    dir_data=$(ws._get_dir "$ws" "$dir")
    includes=$(ws.dir._get_includes "$dir_data") || exit 1
    excludes=$(ws.dir._get_excludes "$dir_data") || exit 1
    tag.generate "$dir" "$tagfile" "$includes" "$excludes"
  done
}

###############
# ws.update_vcs(ws, [dir]?)
###############
function ws.update_vcs {
  local ws dirs

  ws="$1"
  if (( $# > 1 )); then
    dirs="${@:2}"
  else
    dirs=$(ws._get_dirs "$ws") || exit 1
  fi
  for dir in $dirs; do
    git.update_repo "$dir" || exit 1
  done
}

################################################################################
### package tag
################################################################################

###############
# tag.generate(dir, tag_file='TAGS,
#              include_patterns='*', exclude_patterns='',
#              is_tracked_only=true)
# note: includes/excludes are pcre patterns, eg '\.java$|\.groovy$'.
# returns: n/a
# output: 0 if all successfull
###############
function tag.generate {
  local dir tag_file includes excludes is_tracked_only files_cmd perl_cmd

  dir="$1"
  tag_file="${2:-$dir/TAGS}"
  includes="${3:-.*}"
  excludes="${4:-^\$}"
  is_tracked_only="${5:-true}"
  #
  pushd "$dir"
  if [[ "$is_tracked_only" == 'true' ]]; then
    files_cmd="git ls-tree -r --name-only @"
  else
    files_cmd="find $dir -type f -name '*'"
  fi
  perl_cmd="print \"$dir/\$_\" if /($includes)/ && !/($excludes)/"
  #
  $files_cmd \
    | perl -nE"$perl_cmd" \
    | ctags -a -L - -e -u --extras=-fqrs --fields=+aNFE -f "$tag_file"
  popd
}

set +o nounset

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

####################################################################################################
# _.array_contains VALUE *ELEMENT
#
# Checks if VALUE is found in ELEMENTs.
#
# Example
#
#   A=( foo bar baz )
#   $ _array_contains bar "$A[*]" && echo "It should return 0"
#   > It should return 0
#   $ _array_contains lorem "$A[*]" || echo "It should return 1"
#   > It should return 1
#
# @param VALUE Value to check
# @param *ELEMENT Array elements
# @return 0 if found, 1 otherwise.
# @output N/A
####################################################################################################

function _.array_contains {
  local value="$1"

  local element
  for element in ${@:2}; do
    if [[ "$element" == "$value" ]]; then
      return 0
    fi
  done
  return 1
}

####################################################################################################
# _.all_in_path CMD
#
# Searches PATH for all entries containg CMD.
#
# Example:
#  $ echo $(_.all_in_path make)
#  > /usr/bin/make /bin/make
#  $ echo $(_.all_in_path non-existing-command)
#  >
#
# @param CMD Name of the command
# @output All matching entries in PATH as absolute paths to CMD
# @return 0
####################################################################################################

function _.all_in_path {
  local cmd="$1"
  local paths=( "${PATH//:/ }" )
  local matching_abspaths=()
  for path in ${paths[@]}; do
    local abspath="$path/$cmd"
    if [[ -x "$abspath" ]] && ! _.array_contains "$abspath" "${matching_abspaths[*]}"; then
      matching_abspaths+=( "$abspath" )
      echo $abspath
    fi
  done
}

####################################################################################################
# _.next_in_path CMD DIR
#
# Finds the next entry in PATh which contains CMD.
#
# Example:
#
#  $ echo $(_.next_in_path make /usr/bin)
#  > /bin/make
#  $ echo $(_.next_in_path make /bin)
#  >
#
# @param CMD Name of the command
# @param DIR Absolute path to the directory containing CMD
# @output Absolute path to the next occurence of `command` in PATH
# @return 1 if no other occurence of `command` is found in PATH, 0 otherwise.
####################################################################################################

function _.next_in_path {
  local cmd="$1"
  local current_dir="$2"
  local current_abspath="$2/$1"
  local all=( $(_.all_in_path $cmd) )
  local found_current_cmd=false

  for entry in ${all[@]}; do
    if [[ "$entry" == "$current_abspath" ]]; then
      found_current_cmd=true
    elif [[ "$found_current_cmd" == true ]]; then
      echo $entry
      return 0
    fi
  done
  return 1
}

set +o nounset

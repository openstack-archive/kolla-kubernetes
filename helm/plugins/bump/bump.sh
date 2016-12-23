#!/bin/bash

# bump the version of a helm chart
# by default increment the patch (z) version
# optionally increment or explicity set major (x) minor (y) patch (z) 

ARG_X=""
ARG_Y=""
ARG_Z=""
SRC_X=""
SRC_Y=""
SRC_Z=""
XINC=false
YINC=false
ZINC=false
CHARTDIR="."
DEBUG=false
FORCE=false
VERBOSE=false
DRY_RUN=false
OUT=""

function usage(){
  echo "increment a chart version by z (default) or x or y"
  echo "Usage: helm bump \<options\> \<chart path\>"
  echo "Ex. helm bump microservices/heat-api"
  exit 1
}

function force_required(){
  echo "Error: You must use -f or --force to decrement a version"
  exit 1
}
function doube_opt(){
  echo "Error: cannot specify both options $1 and $2"
  exit 1
}
function debug(){
  if [[ $DEBUG == true ]]
  then
    echo $1
  fi
}
function extract_version(){
  BASEPATH=$1
  SRCVER=$(grep "[vV]ersion:" "$BASEPATH/Chart.yaml")
  regex="[vV]ersion: ([0-9]*)\.([0-9]*)\.([0-9]*)"
  if [[ "$SRCVER" =~ $regex ]]
  then
    SRC_X="${BASH_REMATCH[1]}"  
    SRC_Y="${BASH_REMATCH[2]}"  
    SRC_Z="${BASH_REMATCH[3]}"  
    
    debug "Existing version: $SRC_X.$SRC_Y.$SRC_Z"
  else
    echo "Error: Valid version not found in $BASEPATH"
  fi
}
# parse flags
for i in "$@"
do
case $i in
    -x=*|--major=*)
    ARG_X="${i#*=}"
    ;;

    -x|--major)
    XINC=true
    ;;
    -y=*|--minor=*)
    ARG_Y="${i#*=}"
    ;;
    -y|--minor)
    if [[ "x$ARG_Y" == "x" ]] 
    then
      YINC=true
    else
      doulbt_opt "-y" "-y=|--minor="
    fi 
    ;;
    -z=*|--patch=*)
    ARG_Z="${i#*=}"
    ;;
    -z|--patch)
    ZINC=true
    ;;
    --debug)
    DEBUG=true
    ;;
    -f|--force)
    FORCE=true
    ;;
    -v|--verbose)
    VERBOSE=true
    ;;
    --dry-run)
    DRY_RUN=true
    ;;
    *)
    CHARTDIR="$i"
    ;;
esac
done


if [[ ! -d "$CHARTDIR" ]] || [[ ! -f "$CHARTDIR/Chart.yaml" ]]
then
  echo "The first argument must be valid path to chart directory"
  exit 1
fi
extract_version $CHARTDIR
USER_VERSION="x $ARG_X y $ARG_Y z $ARG_Z"
debug "User explicit values: $USER_VERSION"
debug "Increment flags: x $XINC y $YINC z $ZINC"
# set user arg or default to chart version 
function process_point(){
  USER=$1
  EXIST=$2
  INC=$3
  OUT=""
  # if user supplied version part use that
  if [[ "x$USER" != "x" ]]
  then
    if [[ $USER -ge $EXIST ]] 
    then 
      OUT=$USER
    else
      if  [[ "$FORCE" == true ]]
      then
        debug "decrement was forced"
        OUT=$USER
      else
        force_required
        # dont decrement without --force
      fi
    fi
  else
    # if just a increment
    if [[ $INC == true ]] 
    then
      let "OUT = $EXIST + 1"
    else
      # otherwise use exiting chart version
      let "OUT = $EXIST"
    fi
  fi

}

process_point "$ARG_X" $SRC_X $XINC
OUT_X=$OUT
process_point "$ARG_Y" $SRC_Y $YINC
OUT_Y=$OUT
process_point "$ARG_Z" $SRC_Z $ZINC
OUT_Z=$OUT

# just bump z if no xzy change
if [[  "x$ARG_X" == "x" ]] && [[ "x$ARG_Y" == "x" ]] && [[ "x$ARG_Z" == "x" ]]
then
  if [[ $XINC == false ]] && [[ $YINC == false ]] && [[ $ZINC == false ]]
  then 
    debug "defaulting to increment of z"
    let "OUT_Z += 1"
  fi
fi
FINAL_VERSION="$OUT_X.$OUT_Y.$OUT_Z"
debug "Final version: $FINAL_VERSION"
if [[ $VERBOSE == true ]] && [[ $DEBUG == false ]]
then
  echo "$FINAL_VERSION"
fi
if [[ $DRY_RUN == false ]] && [[ $VERBOSE == false ]]
then
  sed -i 's/\(version: \).*/\1'"$FINAL_VERSION"'/i' "$CHARTDIR/Chart.yaml"
fi

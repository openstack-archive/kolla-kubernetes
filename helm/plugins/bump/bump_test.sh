#!/bin/bash

# quick testing for bump

# reset the chart
cp test/good/Chart.yaml.fixture test/good/Chart.yaml

BASECMD="bump.sh -v --dry-run "
FAILED=0
PASSED=0
GOODDIR="test/good"
BADDIR="test/bad"

function run_test(){
  CLI=$1
  EXPECTED=$2
  RESULT="$(`pwd`/$BASECMD $CLI)"
  if [[ $EXPECTED == $RESULT ]]
  then
    PASSFAIL="\e[92mPASS\e[0m"
    let "PASSED = $PASSED + 1"
  else
    PASSFAIL="\e[31mFAIL\e[0m"
    let "FAILED= $FAILED + 1"
  fi
  echo -e "$PASSFAIL ($CLI) $RESULT == $EXPECTED"
}

echo "STATUS CMD RESULT EXPECTED"
echo "** default **"
run_test "$GOODDIR " "4.4.5"
echo "** named increments **"
run_test "$GOODDIR  -x" "5.4.4"
run_test "$GOODDIR  -y" "4.5.4"
run_test "$GOODDIR  -z" "4.4.5"
run_test "$GOODDIR  -x -y -z" "5.5.5"
echo "** user explicit values **"
run_test "$GOODDIR  -x=6" "6.4.4"
run_test "$GOODDIR  -y=6" "4.6.4"
run_test "$GOODDIR  -z=6" "4.4.6"
echo "** forced decrements **"
run_test "$GOODDIR  -f -x=3" "3.4.4"
run_test "$GOODDIR  -f -y=3" "4.3.4"
run_test "$GOODDIR  -f -z=3" "4.4.3"
run_test "$GOODDIR  -f -x=3 -y=3 -z=3" "3.3.3"
echo "** missing dir arg **"
run_test " -v " "The first argument must be valid path to chart directory"
echo "** require force for decrement **"
run_test "$GOODDIR -v -x=3" "Error: You must use -f or --force to decrement a version"
echo "** no chart in dir **"
run_test "$BADDIR" "The first argument must be valid path to chart directory"
echo "** invalid versions **"
echo "** capital Version **"
run_test "test/cap -x" "5.4.4"

# test sed replacement
BASECMD="bump.sh -v "
./bump.sh "$GOODDIR" -x
OUT=$(grep version:.* test/good/Chart.yaml)
SED_MSG="version in test chart file was successfully replaced."
if [[ $OUT == "version: 5.4.4" ]] || [[ $OUT == "Version: 5.4.4" ]]
then
  echo -e "\e[92mPASS\e[0m" - "$SED_MSG"
  let "PASSED = $PASSED + 1"
else
  echo -e "\e[31mFAIL\e[0m" - " $SED_MSG" 
  let "FAILED = $FAILED + 1"
fi

# reset the chart
cp test/good/Chart.yaml.fixture test/good/Chart.yaml

# print test pass/fail count
echo -e "Passed: \e[92m$PASSED\e[0m Failed: \e[31m$FAILED\e[0m"

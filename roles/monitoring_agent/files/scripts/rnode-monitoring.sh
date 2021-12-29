#!/usr/bin/env bash

# ilya.vasilev@itglobal.com, 2021
# https://itgold.io
# https://github.com/itgoldio


### vars
# states for exit codes
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown

getScriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
cd $getScriptDir

source ton-env.sh

# utils
bcBin=$( which bc )
bcArgs=" -ql "
bcLib="${getScriptDir}/bcLibForFloating"

grepBin=$( which grep )
cutBin=$( which cut )
trBin=$( which tr )
tailBin=$( which tail )
tailLines=100
headBin=$( which head )
divideValue=1000000000

version="0.6.0"

# show usage/help info and exit
usage() {
  echo "Usage: $0, ver. ${version}
-h   -- this help
-w   -- warning
-c   -- critical
-C   -- tonos-cli config file
-t   -- type
      
    These checks calls without -w and -c params:
          isValidatingNow
          isValidatingNext

    These checks requires warning and critical param:
          dePoolBalance
          timeDiff


  " 1>&2
  exit $STATE_UNKNOWN
}


getTonosCliVersion() {
  $TON_CLI --version | grep tonos_cli | awk '{print $2}'
}

getRNodeVersion() {
  $RNODE_BIN --version | grep version | awk '{print $4}'
}

getDePoolBalance() {

  versionAsNumber=$( echo "$( getTonosCliVersion)" | sed 's/\.//g' )
  if [[ $versionAsNumber -le 0246 ]]
  then
    myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG account $DEPOOL_ADDR | jq -r ".balance" )
  else
    myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG account $DEPOOL_ADDR | jq -r ".[].balance" )
  fi
  [[ -n $myRes ]] && echo $myRes || echo ""
}

checkStatus() {

  # *Balance - using script ./ton-*-balance.sh
  #   returning values from script: long
  #   returning code by check should be prepared:
  #     value / 1000000000 ? 30 >     -> 0 - ok
  #     value / 1000000000 ? 20..29   -> 1 - warn
  #     value / 1000000000 ? 19 <     -> 2 - crit
  #                                   -> 3 - unknown
  #    23.06.2021 - Dont using rounding now =)
  #     43772151034
  #    25.06.2021 - lets round!!!

  type=${1}
  warnValue=${2}
  critValue=${3}
  curValue=${4}
    
  case "$type" in
    walletBalance ) myMsg="Node wallet balance:" ;;
    dePoolBalance ) curValue=$( getDePoolBalance ) ; myMsg="DePool balance:" ;;
    proxy1balance ) myMsg="DePool proxy 1 balance:" ;;
    proxy2balance ) myMsg="DePool proxy 2 balance:" ;;
    tickTokBalance ) myMsg="TickTok balance:" ;;
  esac

  if [[ -z $curValue ]]
  then
    echo "UNKNOWN - $myMsg -1 | $type=-1;$warnValue;$critValue;;"
    exit $STATE_UNKNOWN
  fi

  evalRes=$( echo "$curValue/$divideValue" | ${bcBin} ${bcArgs} ${bcLib} )
  isWarn=$( echo "$evalRes<=$warnValue" | ${bcBin} ${bcArgs} ${bcLib} )
  isCrit=$( echo "$evalRes<=$critValue" | ${bcBin} ${bcArgs} ${bcLib} )

  if [[ $isWarn -ne 1 && $isCrit -ne 1 ]]
  then
    echo "OK - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_OK
  elif [[ $isWarn -eq 1 && $isCrit -ne 1 ]]
  then
    echo "WARNING - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_WARNING
  elif [[ $isCrit -eq 1 ]]
  then
    echo "CRITICAL - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_CRITICAL
  else
    echo "UNKNOWN - $myMsg $evalRes | $type=$evalRes;$warnValue;$critValue;;"
    exit $STATE_UNKNOWN
  fi
}

getElectorAddr(){
  $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c 'getconfig 1' | grep -iq error
  if [[ $? -ne 0 ]]
  then
    myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getconfig 1" | jq -r '.p1' )
    [[ -n $myRes ]] && echo "-1:${myRes}" || echo ""
  fi
}

getCurrentElectionsID() {
  # Ровно до тех пор пока мы едем в мейне на фифте
  # fift
  myRes=$( $TON_CLI -j -c $TON_CLI_CONFIG runget $( getElectorAddr ) active_election_id | jq -r ".value0" )
  [[ -n $myRes ]] && echo "${myRes}" || echo ""
  # solidity
  # myRes=$( $TON_CLI -j run $( getElectorAddr ) active_election_id '{}' --abi ${Elector_ABI} | jq -r '.value0')
  # [[ -n $myRes ]] && echo "${myRes}" || echo ""
}

getAccountBalance() {
  myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getaccount $VALIDATOR_WALLET_ADDR" | jq -r ".balance" )
  [[ -n $myRes ]] && echo $myRes || echo ""
}

isValidatingNow() {
  myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getstats" | jq -r ".in_current_vset_p34" )
  [[ -n $myRes ]] && echo $myRes || echo ""
}

isValidatingNext() {
utime=$( date +%s )

# в этот период проверяем
TON_CURRENT_VALIDATION_END=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getconfig 34"  | jq -r ".p34.utime_until" )
TON_ELECTIONS_START_BEFORE=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getconfig 15"  | jq -r ".p15.elections_start_before" )

if [[ -z $TON_CURRENT_VALIDATION_END || -z $TON_ELECTIONS_START_BEFORE ]]
then
  echo -e "UNKNOWN - no data in .p34.utime_until or .p15.elections_start_before | validatingNext=-1;;;;"
  exit $STATE_UNKNOWN
fi

TON_ELECTIONS_START=$(($TON_CURRENT_VALIDATION_END - $TON_ELECTIONS_START_BEFORE))

if [[ $utime -ge $TON_ELECTIONS_START && $utime -le $TON_CURRENT_VALIDATION_END ]]
then
  myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getstats" | jq -r ".in_next_vset_p36" )
  if [[ "$myRes" == "true" ]]
  then
    echo "OK - Node will validate next round: 1 | validatingNext=1;;;;"
    exit $STATE_OK
  else
    echo "CRITICAL - Node will validate next round: 0 | validatingNext=0;;;;"
    exit $STATE_CRITICAL
  fi
else
  echo -e "UNKNOWN - Elections not defined yet | validatingNext=-1;;;;"
  exit $STATE_OK
fi
}

getTimeDiff() {
# timeDiff  - using script ./ton-node-diff.sh
#   returning values from script: integer
#   checking values and returning code by check
#     1 sec - 600 sec  - normal -> return 0
#     600 sec - 1199 sec - warning -> return 1
#     1200 sec > - critical -> return 2
#     0 < - unknown -> unknown 3
  warnValue=${1}
  critValue=${2}
  myRes=$( $TON_CONSOLE -j -C $TON_CONSOLE_CONFIG -c "getstats" | jq -r ".timediff" )
  if [[ "$myRes" -lt "$warnValue" ]]
  then
    echo "OK - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_OK
  elif [[ "$myRes" -ge "$warnValue" && "$myRes" -lt "$critValue" ]]
  then
    echo "WARNING - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_WARNING
  elif [[ "$myRes" -ge "$critValue" ]]
  then
    echo "CRITICAL - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_CRITICAL
  else
    echo "UNKNOWN - Node time diff: $myRes | timeDiff=$myRes;${warnValue};${critValue};;"
    exit $STATE_UNKNOWN
  fi
}

### main script

if [ -z "${1}" ]
then
  usage
fi

while getopts ":w:c:t:hC:" myArgs
do
  case ${myArgs} in
    w) warnValue=${OPTARG} ;;
    c) critValue=${OPTARG} ;;
    t) typeCheck=${OPTARG} ;;
    C) configFile=${OPTARG} ;;
    h) usage ;;
    \?)  echo "Wrong option given. Check help ( $0 -h ) for usage."
        exit $STATE_UNKNOWN
        ;;
  esac
done

if [[ "${typeCheck}" == "isValidatingNow" ]]
then
  isValidatingNow
elif [[ "${typeCheck}" == "isValidatingNext" ]]
then
  isValidatingNext
elif [[ -n "${typeCheck}" && -n "${warnValue}" && -n "${critValue}" ]]
then
  while true
  do
    case "$typeCheck" in
      timeDiff ) getTimeDiff "${warnValue}" "${critValue}" ;;
      walletBalance )
        checkStatus walletBalance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${walletBalanceScript}" ) ;;
      dePoolBalance )
        checkStatus dePoolBalance "${warnValue}" "${critValue}" ;;
      proxy1balance )
        checkStatus proxy1balance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${depoolproxy1BalanceScript}" 2>/dev/null ) ;;
      proxy2balance )
        checkStatus proxy2balance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${depoolproxy2BalanceScript}" 2>/dev/null ) ;;
      tickTokBalance )
        checkStatus tickTokBalance "${warnValue}" "${critValue}" $( "${tonScriptsDir}""${tickTokBalanceScript}" ) ;;
      * )
        usage
        exit ${STATE_UNKNOWN}
        ;;
    esac
  done
else
  echo -e "Missing required parameter or parameters"
  usage
  exit ${STATE_UNKNOWN}
fi
